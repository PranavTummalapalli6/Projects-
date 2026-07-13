import { Module } from '@nestjs/common';
import { RetrievalService } from './retrieval.service';
import { EmbeddingsModule } from '../embeddings/embeddings.module';

@Module({
  imports: [EmbeddingsModule],
  providers: [RetrievalService],
  exports: [RetrievalService],
})
export class RetrievalModule {}
