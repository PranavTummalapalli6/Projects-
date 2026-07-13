import { Module } from '@nestjs/common';
import { SearchDocumentsTool } from './search-documents.tool';
import { CalculatorTool } from './calculator.tool';
import { CurrentTimeTool } from './current-time.tool';
import { SendEmailTool } from './send-email.tool';
import { RetrievalModule } from '../retrieval/retrieval.module';
import { N8nModule } from '../n8n/n8n.module';

@Module({
  imports: [RetrievalModule, N8nModule],
  providers: [SearchDocumentsTool, CalculatorTool, CurrentTimeTool, SendEmailTool],
  exports: [SearchDocumentsTool, CalculatorTool, CurrentTimeTool, SendEmailTool],
})
export class ToolsModule {}
