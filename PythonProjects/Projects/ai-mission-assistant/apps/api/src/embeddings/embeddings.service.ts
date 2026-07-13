import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';

/**
 * EmbeddingsService is the single place that talks to the embedding provider.
 * The rest of the app calls embed() — swapping providers means only changing here.
 */
@Injectable()
export class EmbeddingsService {
  private readonly logger = new Logger(EmbeddingsService.name);
  private openai: OpenAI;
  private model: string;

  constructor(private config: ConfigService) {
    const apiKey = this.config.get<string>('llm.apiKey');
    this.model = this.config.get<string>('embedding.model') ?? 'text-embedding-3-small';

    this.openai = new OpenAI({ apiKey });
  }

  /**
   * Converts text into a vector embedding array.
   * Returns a float[] with EMBEDDING_DIMENSIONS values (default 1536).
   */
  async embed(text: string): Promise<number[]> {
    try {
      const response = await this.openai.embeddings.create({
        model: this.model,
        input: text.replace(/\n/g, ' '), // OpenAI recommends replacing newlines
      });
      return response.data[0].embedding;
    } catch (err) {
      this.logger.error('Embedding API call failed:', err);
      throw new ServiceUnavailableException('Embedding service unavailable');
    }
  }
}
