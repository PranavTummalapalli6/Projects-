import { Module } from '@nestjs/common';
import { IngestionService } from './ingestion.service';
import { ChunkerService } from './chunker.service';
import { EmbeddingsModule } from '../embeddings/embeddings.module';

@Module({
  imports: [EmbeddingsModule],
  providers: [IngestionService, ChunkerService],
  exports: [IngestionService],
})
export class IngestionModule {}
