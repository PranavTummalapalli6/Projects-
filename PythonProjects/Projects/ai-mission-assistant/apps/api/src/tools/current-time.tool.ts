import { Injectable } from '@nestjs/common';
import { AgentTool, ToolContext } from './tools.interface';

@Injectable()
export class CurrentTimeTool implements AgentTool {
  name = 'current_time';
  description =
    'Get the current date and time, optionally for a specific timezone or city.';

  parameters = {
    type: 'object',
    properties: {
      timezone: {
        type: 'string',
        description: 'IANA timezone string (e.g. "America/New_York") or city name. Defaults to UTC.',
      },
    },
    required: [],
  };

  async execute(input: unknown, _context: ToolContext) {
    const { timezone } = (input ?? {}) as { timezone?: string };

    const tz = this.resolveTimezone(timezone);

    try {
      const now = new Date();
      const formatted = new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        dateStyle: 'full',
        timeStyle: 'long',
      }).format(now);

      return { timezone: tz, datetime: formatted, iso: now.toISOString() };
    } catch {
      return { timezone: 'UTC', datetime: new Date().toUTCString(), iso: new Date().toISOString() };
    }
  }

  private resolveTimezone(input?: string): string {
    if (!input) return 'UTC';

    // Common city → IANA mapping
    const cityMap: Record<string, string> = {
      'new york': 'America/New_York',
      'los angeles': 'America/Los_Angeles',
      'chicago': 'America/Chicago',
      'london': 'Europe/London',
      'paris': 'Europe/Paris',
      'berlin': 'Europe/Berlin',
      'tokyo': 'Asia/Tokyo',
      'sydney': 'Australia/Sydney',
      'dubai': 'Asia/Dubai',
      'mumbai': 'Asia/Kolkata',
    };

    const normalized = input.toLowerCase().trim();
    return cityMap[normalized] ?? input;
  }
}
