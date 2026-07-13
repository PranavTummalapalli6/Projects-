import { IsString, IsOptional, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class SendMessageDto {
  @ApiProperty({ example: 'What is the vacation policy?' })
  @IsString()
  @MinLength(1)
  content: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  conversationId?: string;
}

export class CreateConversationDto {
  @ApiProperty({ example: 'Vacation Policy Questions', required: false })
  @IsOptional()
  @IsString()
  title?: string;
}
