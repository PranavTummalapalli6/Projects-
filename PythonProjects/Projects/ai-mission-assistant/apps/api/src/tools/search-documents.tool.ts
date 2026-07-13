import { Injectable } from '@nestjs/common';
import { AgentTool, ToolContext } from './tools.interface';
import { RetrievalService } from '../retrieval/retrieval.service';

@Injectable()
export class SearchDocumentsTool implements AgentTool {
  name = 'search_documents';
  description =
    'Search the user\'s uploaded documents for information. Use this when the user asks about policies, procedures, or content from their documents.';

  parameters = {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        description: 'The search query to find relevant document content',
      },
    },
    required: ['query'],
  };

  constructor(private retrieval: RetrievalService) {}

  async execute(input: unknown, context: ToolContext) {
    const { query } = input as { query: string };
    const chunks = await this.retrieval.search(query, context.userId);

    if (chunks.length === 0) {
      return { found: false, message: 'No relevant documents found for this query.' };
    }

    return {
      found: true,
      chunks: chunks.map((c) => ({
        content: c.content,
        source: c.documentName,
        chunkIndex: c.chunkIndex,
        pageNumber: c.pageNumber,
        relevanceScore: Math.round(c.similarity * 100) / 100,
      })),
    };
  }
}
