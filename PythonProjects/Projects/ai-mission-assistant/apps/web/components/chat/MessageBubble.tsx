'use client';

import { Message } from '@/types';
import { Bot, User, Wrench } from 'lucide-react';

interface Props {
  message: Message;
  toolsUsed?: string[];
}

export function MessageBubble({ message, toolsUsed }: Props) {
  const isAssistant = message.role === 'assistant';

  return (
    <div className={`flex gap-3 ${isAssistant ? 'items-start' : 'items-start flex-row-reverse'}`}>
      {/* Avatar */}
      <div
        className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${
          isAssistant ? 'bg-blue-600' : 'bg-gray-600'
        }`}
      >
        {isAssistant ? <Bot size={16} /> : <User size={16} />}
      </div>

      {/* Content */}
      <div className={`flex flex-col gap-1 max-w-[80%] ${isAssistant ? '' : 'items-end'}`}>
        {/* Tool indicator */}
        {isAssistant && toolsUsed && toolsUsed.length > 0 && (
          <div className="flex items-center gap-1 text-xs text-gray-400">
            <Wrench size={11} />
            <span>Used: {toolsUsed.join(', ')}</span>
          </div>
        )}

        {/* Message bubble */}
        <div
          className={`rounded-2xl px-4 py-3 text-sm leading-relaxed whitespace-pre-wrap ${
            isAssistant
              ? 'bg-gray-800 text-gray-100 rounded-tl-sm'
              : 'bg-blue-600 text-white rounded-tr-sm'
          }`}
        >
          {message.content}
        </div>

        <span className="text-xs text-gray-500">
          {new Date(message.createdAt).toLocaleTimeString([], {
            hour: '2-digit',
            minute: '2-digit',
          })}
        </span>
      </div>
    </div>
  );
}
