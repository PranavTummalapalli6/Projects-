import { Injectable } from '@nestjs/common';

export interface TextChunk {
  content: string;
  chunkIndex: number;
  pageNumber?: number;
}

const CHUNK_SIZE = 3200;   // ~800 tokens at ~4 chars/token
const OVERLAP_SIZE = 800;  // ~200 tokens overlap between consecutive chunks

@Injectable()
export class ChunkerService {
  /**
   * Splits text into overlapping chunks using paragraph-aware strategy.
   *
   * Algorithm:
   *  1. Split on double-newline paragraph boundaries
   *  2. Accumulate paragraphs until the chunk reaches CHUNK_SIZE chars
   *  3. Save the chunk, then start the next chunk with the last OVERLAP_SIZE
   *     chars of the previous chunk so context is not lost at boundaries
   *
   * Why paragraphs: semantic units — a sentence about vacation policy should
   * not be split across two chunks, losing the surrounding context.
   */
  chunk(text: string): TextChunk[] {
    const paragraphs = text
      .split(/\n{2,}/)
      .map((p) => p.trim())
      .filter((p) => p.length > 0);

    const chunks: TextChunk[] = [];
    let current = '';
    let chunkIndex = 0;

    for (const para of paragraphs) {
      const tentative = current ? `${current}\n\n${para}` : para;

      if (tentative.length > CHUNK_SIZE && current.length > 0) {
        chunks.push({ content: current.trim(), chunkIndex: chunkIndex++ });
        // Overlap: carry forward the tail of the previous chunk
        const overlap = current.slice(-OVERLAP_SIZE);
        current = overlap ? `${overlap}\n\n${para}` : para;
      } else {
        current = tentative;
      }
    }

    if (current.trim().length > 0) {
      chunks.push({ content: current.trim(), chunkIndex: chunkIndex });
    }

    return chunks;
  }
}
