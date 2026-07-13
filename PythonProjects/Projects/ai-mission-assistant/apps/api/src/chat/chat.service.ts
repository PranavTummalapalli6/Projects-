import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AgentService } from '../agent/agent.service';
import { SendMessageDto, CreateConversationDto } from './dto/chat.dto';

@Injectable()
export class ChatService {
  constructor(
    private prisma: PrismaService,
    private agent: AgentService,
  ) {}

  async createConversation(userId: string, dto: CreateConversationDto) {
    return this.prisma.conversation.create({
      data: { userId, title: dto.title ?? 'New Conversation' },
    });
  }

  async listConversations(userId: string) {
    return this.prisma.conversation.findMany({
      where: { userId },
      select: {
        id: true,
        title: true,
        createdAt: true,
        updatedAt: true,
        _count: { select: { messages: true } },
      },
      orderBy: { updatedAt: 'desc' },
    });
  }

  async getConversation(id: string, userId: string) {
    const convo = await this.prisma.conversation.findUnique({
      where: { id },
      include: { messages: { orderBy: { createdAt: 'asc' } } },
    });
    if (!convo) throw new NotFoundException('Conversation not found');
    if (convo.userId !== userId) throw new ForbiddenException();
    return convo;
  }

  async sendMessage(userId: string, userEmail: string, dto: SendMessageDto) {
    // Create or reuse conversation
    let conversationId = dto.conversationId;

    if (!conversationId) {
      const convo = await this.prisma.conversation.create({
        data: {
          userId,
          title: dto.content.slice(0, 60), // use the first message as title
        },
      });
      conversationId = convo.id;
    } else {
      // Validate ownership
      const convo = await this.prisma.conversation.findUnique({
        where: { id: conversationId },
      });
      if (!convo) throw new NotFoundException('Conversation not found');
      if (convo.userId !== userId) throw new ForbiddenException();
    }

    // Save the user's message
    await this.prisma.message.create({
      data: { conversationId, role: 'user', content: dto.content },
    });

    // Fetch recent conversation history for context
    const history = await this.prisma.message.findMany({
      where: { conversationId },
      orderBy: { createdAt: 'asc' },
      take: 20,
    });

    const conversationHistory = history
      .slice(0, -1) // exclude the message we just added
      .map((m) => ({
        role: m.role as 'user' | 'assistant',
        content: m.content,
      }));

    // Run the agent
    const agentResult = await this.agent.run(dto.content, conversationHistory, {
      userId,
      conversationId,
      userEmail,
    });

    // Save the assistant's response
    const assistantMessage = await this.prisma.message.create({
      data: {
        conversationId,
        role: 'assistant',
        content: agentResult.content,
      },
    });

    // Touch the conversation updatedAt
    await this.prisma.conversation.update({
      where: { id: conversationId },
      data: { updatedAt: new Date() },
    });

    return {
      conversationId,
      message: assistantMessage,
      toolsUsed: agentResult.toolsUsed,
    };
  }

  async deleteConversation(id: string, userId: string) {
    const convo = await this.prisma.conversation.findUnique({ where: { id } });
    if (!convo) throw new NotFoundException('Conversation not found');
    if (convo.userId !== userId) throw new ForbiddenException();
    await this.prisma.conversation.delete({ where: { id } });
    return { message: 'Conversation deleted' };
  }
}
