import { Injectable } from '@nestjs/common';
import { create, all } from 'mathjs';
import { AgentTool, ToolContext } from './tools.interface';

// mathjs is a safe math parser — no eval, no code execution
const math = create(all, { matrix: 'Array' });

@Injectable()
export class CalculatorTool implements AgentTool {
  name = 'calculator';
  description =
    'Evaluate mathematical expressions. Use for arithmetic, percentages, and numerical calculations.';

  parameters = {
    type: 'object',
    properties: {
      expression: {
        type: 'string',
        description: 'Mathematical expression to evaluate, e.g. "18% of 4750" or "1234 * 57"',
      },
    },
    required: ['expression'],
  };

  async execute(input: unknown, _context: ToolContext) {
    const { expression } = input as { expression: string };

    // Normalize "X% of Y" to "X/100 * Y" which mathjs can evaluate
    const normalized = expression.replace(
      /(\d+(?:\.\d+)?)\s*%\s*of\s*(\d+(?:\.\d+)?)/gi,
      '($1/100) * $2',
    );

    try {
      const result = math.evaluate(normalized);
      return {
        expression,
        result: typeof result === 'number' ? Math.round(result * 1000) / 1000 : String(result),
      };
    } catch {
      return { error: `Could not evaluate: "${expression}"` };
    }
  }
}
