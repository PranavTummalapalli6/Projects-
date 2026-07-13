import { Injectable } from '@nestjs/common';
import { AgentTool, ToolContext } from './tools.interface';
import { N8nService } from '../n8n/n8n.service';

@Injectable()
export class SendEmailTool implements AgentTool {
  name = 'send_email';
  description =
    'Send an email via the n8n workflow. Use when the user explicitly asks to email something. The "to" field defaults to the user\'s own email if not specified.';

  parameters = {
    type: 'object',
    properties: {
      to: {
        type: 'string',
        description: 'Recipient email address',
      },
      subject: {
        type: 'string',
        description: 'Email subject line',
      },
      body: {
        type: 'string',
        description: 'Email body content (plain text or HTML)',
      },
    },
    required: ['to', 'subject', 'body'],
  };

  constructor(private n8n: N8nService) {}

  async execute(input: unknown, context: ToolContext) {
    const { to, subject, body } = input as {
      to: string;
      subject: string;
      body: string;
    };

    // Default recipient to the authenticated user's email
    const recipient = to || context.userEmail || '';

    return this.n8n.sendEmail({ to: recipient, subject, body });
  }
}
