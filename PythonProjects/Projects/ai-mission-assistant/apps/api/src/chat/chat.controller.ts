import { Controller, Post, Get, Delete, Param, Body, UseGuards, Request } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ChatService } from './chat.service';
import { SendMessageDto, CreateConversationDto } from './dto/chat.dto';

interface AuthRequest {
  user: { id: string; email: string };
}

@ApiTags('chat')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class ChatController {
  constructor(private chatService: ChatService) {}

  @Post('conversations')
  @ApiOperation({ summary: 'Start a new conversation' })
  create(@Body() dto: CreateConversationDto, @Request() req: AuthRequest) {
    return this.chatService.createConversation(req.user.id, dto);
  }

  @Get('conversations')
  @ApiOperation({ summary: 'List all conversations' })
  list(@Request() req: AuthRequest) {
    return this.chatService.listConversations(req.user.id);
  }

  @Get('conversations/:id')
  @ApiOperation({ summary: 'Get conversation with messages' })
  get(@Param('id') id: string, @Request() req: AuthRequest) {
    return this.chatService.getConversation(id, req.user.id);
  }

  @Delete('conversations/:id')
  @ApiOperation({ summary: 'Delete a conversation' })
  delete(@Param('id') id: string, @Request() req: AuthRequest) {
    return this.chatService.deleteConversation(id, req.user.id);
  }

  @Post('chat')
  @ApiOperation({ summary: 'Send a message to the AI agent' })
  chat(@Body() dto: SendMessageDto, @Request() req: AuthRequest) {
    return this.chatService.sendMessage(req.user.id, req.user.email, dto);
  }
}
