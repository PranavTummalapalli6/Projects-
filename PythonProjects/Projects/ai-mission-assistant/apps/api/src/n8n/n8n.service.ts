import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import fetch from 'node-fetch';

export interface EmailPayload {
  to: string;
  subject: string;
  body: string;
}

@Injectable()
export class N8nService {
  private readonly logger = new Logger(N8nService.name);
  private webhookUrl: string;

  constructor(private config: ConfigService) {
    this.webhookUrl = this.config.get<string>('n8n.webhookUrl')!;
  }

  async sendEmail(payload: EmailPayload): Promise<{ success: boolean; message: string }> {
    try {
      const response = await fetch(this.webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error(`n8n webhook responded with ${response.status}`);
      }

      this.logger.log(`Email sent via n8n to ${payload.to}`);
      return { success: true, message: `Email sent to ${payload.to}` };
    } catch (err) {
      this.logger.error('n8n email webhook failed:', err);
      throw new ServiceUnavailableException(
        'Email service unavailable. Ensure n8n is running and the workflow is active.',
      );
    }
  }
}
