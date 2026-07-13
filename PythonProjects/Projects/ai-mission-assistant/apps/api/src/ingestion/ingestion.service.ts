import { Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs';
// eslint-disable-next-line @typescript-eslint/no-require-imports
const pdfParse = require('pdf-parse') as (buf: Buffer) => Promise<{ text: string; numpages: number }>;
import { PrismaService } from '../prisma/prisma.service';
import { ChunkerService } from './chunker.service';
import { EmbeddingsService } from '../embeddings/embeddings.service';

@Injectable()
export class IngestionService {
  private readonly logger = new Logger(IngestionService.name);

  constructor(
    private prisma: PrismaService,
    private chunker: ChunkerService,
    private embeddings: EmbeddingsService,
  ) {}

  async ingest(documentId: string, filePath: string): Promise<void> {
    try {
      await this.prisma.document.update({
        where: { id: documentId },
        data: { status: 'PROCESSING' },
      });

      // 1. Extract text from PDF
      const buffer = fs.readFileSync(filePath);
      const pdf = await pdfParse(buffer);
      const rawText = pdf.text;

      if (!rawText || rawText.trim().length === 0) {
        throw new Error('PDF contains no extractable text (may be image-only)');
      }

      // 2. Clean text — normalize whitespace but preserve paragraph breaks
      const cleanText = rawText
        .replace(/\r\n/g, '\n')
        .replace(/[ \t]+/g, ' ')
        .replace(/\n{3,}/g, '\n\n')
        .trim();

      // 3. Chunk the text
      const chunks = this.chunker.chunk(cleanText);
      this.logger.log(`Document ${documentId}: ${chunks.length} chunks created`);

      // 4. Generate embeddings and save chunks
      for (const chunk of chunks) {
        let embedding: number[] | null = null;
        try {
          embedding = await this.embeddings.embed(chunk.content);
        } catch (err) {
          this.logger.warn(`Embedding failed for chunk ${chunk.chunkIndex}: ${err}`);
        }

        // Use raw SQL to insert the pgvector embedding column
        if (embedding) {
          await this.prisma.$executeRaw`
            INSERT INTO "DocumentChunk" (id, "documentId", content, "chunkIndex", "pageNumber", metadata, embedding, "createdAt")
            VALUES (
              gen_random_uuid(),
              ${documentId},
              ${chunk.content},
              ${chunk.chunkIndex},
              ${chunk.pageNumber ?? null},
              ${'{}'}::jsonb,
              ${`[${embedding.join(',')}]`}::vector,
              NOW()
            )
          `;
        } else {
          // Save chunk without embedding if embedding failed
          await this.prisma.documentChunk.create({
            data: {
              documentId,
              content: chunk.content,
              chunkIndex: chunk.chunkIndex,
              pageNumber: chunk.pageNumber,
            },
          });
        }
      }

      await this.prisma.document.update({
        where: { id: documentId },
        data: { status: 'INDEXED' },
      });

      this.logger.log(`Document ${documentId} indexed successfully`);
    } catch (err) {
      this.logger.error(`Ingestion failed for document ${documentId}:`, err);
      await this.prisma.document.update({
        where: { id: documentId },
        data: {
          status: 'FAILED',
          errorMessage: err instanceof Error ? err.message : String(err),
        },
      });
    }
  }
}
