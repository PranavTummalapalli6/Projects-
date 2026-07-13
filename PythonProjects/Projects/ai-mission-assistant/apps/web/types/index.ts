export interface Document {
  id: string;
  originalName: string;
  fileSize: number;
  status: 'UPLOADED' | 'PROCESSING' | 'INDEXED' | 'FAILED';
  errorMessage?: string;
  createdAt: string;
  updatedAt: string;
  _count?: { chunks: number };
}

export interface Message {
  id: string;
  conversationId: string;
  role: 'user' | 'assistant';
  content: string;
  createdAt: string;
}

export interface Conversation {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  messages?: Message[];
  _count?: { messages: number };
}

export interface ChatResponse {
  conversationId: string;
  message: Message;
  toolsUsed: string[];
}
