import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EmbeddingsService } from '../embeddings/embeddings.service';

export interface RetrievedChunk {
  id: string;
  documentId: string;
  documentName: string;
  content: string;
  chunkIndex: number;
  pageNumber: number | null;
  similarity: number;
}

@Injectable()
export class RetrievalService {
  private readonly logger = new Logger(RetrievalService.name);

  constructor(
    private prisma: PrismaService,
    private embeddings: EmbeddingsService,
  ) {}

  /**
   * Semantic search over a user's document chunks.
   *
   * 1. Embed the query
   * 2. Use pgvector cosine similarity (<=> operator, lower = more similar)
   * 3. Return top-K chunks with source document info
   *
   * We scope results to the requesting userId so users only see their own docs.
   */
  async search(query: string, userId: string, topK = 5): Promise<RetrievedChunk[]> {
    const queryEmbedding = await this.embeddings.embed(query);
    const vectorLiteral = `[${queryEmbedding.join(',')}]`;

    // Raw SQL required because Prisma doesn't support vector operators natively
    const results = await this.prisma.$queryRaw<
      Array<{
        id: string;
        document_id: string;
        original_name: string;
        content: string;
        chunk_index: number;
        page_number: number | null;
        similarity: number;
      }>
    >`
      SELECT
        dc.id,
        dc."documentId" AS document_id,
        d."originalName" AS original_name,
        dc.content,
        dc."chunkIndex" AS chunk_index,
        dc."pageNumber" AS page_number,
        1 - (dc.embedding <=> ${vectorLiteral}::vector) AS similarity
      FROM "DocumentChunk" dc
      JOIN "Document" d ON d.id = dc."documentId"
      WHERE d."userId" = ${userId}
        AND dc.embedding IS NOT NULL
        AND 1 - (dc.embedding <=> ${vectorLiteral}::vector) > 0.3
      ORDER BY dc.embedding <=> ${vectorLiteral}::vector
      LIMIT ${topK}
    `;

    return results.map((r) => ({
      id: r.id,
      documentId: r.document_id,
      documentName: r.original_name,
      content: r.content,
      chunkIndex: r.chunk_index,
      pageNumber: r.page_number,
      similarity: Number(r.similarity),
    }));
  }
}
