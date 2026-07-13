export interface AgentTool {
  name: string;
  description: string;
  parameters: Record<string, unknown>; // JSON Schema object for the tool's input
  execute(input: unknown, context: ToolContext): Promise<unknown>;
}

export interface ToolContext {
  userId: string;
  conversationId: string;
  userEmail?: string;
}
