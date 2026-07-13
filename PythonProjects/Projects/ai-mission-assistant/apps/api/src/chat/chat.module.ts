import { Module } from '@nestjs/common';
import { ChatService } from './chat.service';
import { ChatController } from './chat.controller';
import { AgentModule } from '../agent/agent.module';

@Module({
  imports: [AgentModule],
  providers: [ChatService],
  controllers: [ChatController],
})
export class ChatModule {}
