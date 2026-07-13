import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';
import { AgentTool, ToolContext } from '../tools/tools.interface';
import { SearchDocumentsTool } from '../tools/search-documents.tool';
import { CalculatorTool } from '../tools/calculator.tool';
import { CurrentTimeTool } from '../tools/current-time.tool';
import { SendEmailTool } from '../tools/send-email.tool';
import { PrismaService } from '../prisma/prisma.service';

export interface AgentResponse {
  content: string;
  toolsUsed: string[];
  retrievedChunks: unknown[];
}

const SYSTEM_PROMPT = `You are an AI Mission Assistant — a professional enterprise knowledge assistant.

When answering questions about documents:
- ONLY use information from the search_documents tool results
- Always cite your sources: mention the document name and chunk reference
- If you cannot find relevant information, say so honestly — do not fabricate content
- If information is not in the retrieved documents, acknowledge uncertainty

When performing calculations, use the calculator tool.
When asked about the current time, use the current_time tool.
When the user asks to send an email, use the send_email tool.

Be concise, professional, and accurate.`;

const MAX_TOOL_ITERATIONS = 5;

@Injectable()
export class AgentService {
  private readonly logger = new Logger(AgentService.name);
  private openai: OpenAI;
  private model: string;
  private tools: Map<string, AgentTool>;

  constructor(
    private config: ConfigService,
    private prisma: PrismaService,
    searchDocuments: SearchDocumentsTool,
    calculator: CalculatorTool,
    currentTime: CurrentTimeTool,
    sendEmail: SendEmailTool,
  ) {
    this.openai = new OpenAI({ apiKey: this.config.get<string>('llm.apiKey') });
    this.model = this.config.get<string>('llm.model') ?? 'gpt-4o';

    // Tool registry
    this.tools = new Map<string, AgentTool>([
      [searchDocuments.name, searchDocuments],
      [calculator.name, calculator],
      [currentTime.name, currentTime],
      [sendEmail.name, sendEmail],
    ]);
  }

  async run(
    userMessage: string,
    conversationHistory: Array<{ role: 'user' | 'assistant'; content: string }>,
    context: ToolContext,
  ): Promise<AgentResponse> {
    const startTime = Date.now();
    const toolsUsed: string[] = [];
    const retrievedChunks: unknown[] = [];

    // Build OpenAI tool definitions from the registered tools
    const toolDefinitions = Array.from(this.tools.values()).map((t) => ({
      type: 'function' as const,
      function: {
        name: t.name,
        description: t.description,
        parameters: t.parameters,
      },
    }));

    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      // Last 10 messages for context (avoid runaway token usage)
      ...conversationHistory.slice(-10),
      { role: 'user', content: userMessage },
    ];

    let iterations = 0;

    // ReAct loop: keep calling the model until it returns a text response (no tool call)
    while (iterations < MAX_TOOL_ITERATIONS) {
      iterations++;

      const completion = await this.openai.chat.completions.create({
        model: this.model,
        messages,
        tools: toolDefinitions,
        tool_choice: 'auto',
      });

      const choice = completion.choices[0];
      const assistantMessage = choice.message;
      messages.push(assistantMessage);

      // No tool call — model produced a final answer
      if (choice.finish_reason !== 'tool_calls' || !assistantMessage.tool_calls) {
        const content = assistantMessage.content ?? '';

        // Log the AI request
        await this.prisma.aIRequestLog.create({
          data: {
            userId: context.userId,
            conversationId: context.conversationId,
            prompt: userMessage,
            retrievedChunks: retrievedChunks as object[],
            selectedTool: toolsUsed[0] ?? null,
            response: content,
            model: this.model,
            latencyMs: Date.now() - startTime,
          },
        });

        return { content, toolsUsed, retrievedChunks };
      }

      // Execute each tool call the model requested
      for (const toolCall of assistantMessage.tool_calls) {
        const fn = (toolCall as { function: { name: string; arguments: string } }).function;
        const toolName = fn.name;
        const toolInput = JSON.parse(fn.arguments);
        const tool = this.tools.get(toolName);

        toolsUsed.push(toolName);

        let toolResult: unknown;
        const toolStart = Date.now();

        try {
          toolResult = tool ? await tool.execute(toolInput, context) : { error: 'Tool not found' };

          // Capture retrieved chunks for logging
          if (toolName === 'search_documents' && (toolResult as { chunks?: unknown[] }).chunks) {
            retrievedChunks.push(...((toolResult as { chunks: unknown[] }).chunks));
          }

          await this.prisma.toolExecution.create({
            data: {
              conversationId: context.conversationId,
              toolName,
              input: toolInput,
              output: toolResult as object,
              status: 'SUCCESS',
              durationMs: Date.now() - toolStart,
            },
          });
        } catch (err) {
          toolResult = { error: err instanceof Error ? err.message : String(err) };
          await this.prisma.toolExecution.create({
            data: {
              conversationId: context.conversationId,
              toolName,
              input: toolInput,
              output: toolResult as object,
              status: 'FAILED',
              durationMs: Date.now() - toolStart,
            },
          });
        }

        // Feed the tool result back to the model
        messages.push({
          role: 'tool',
          tool_call_id: toolCall.id,
          content: JSON.stringify(toolResult),
        });
      }
    }

    return {
      content: 'I was unable to complete the request after multiple attempts.',
      toolsUsed,
      retrievedChunks,
    };
  }
}
