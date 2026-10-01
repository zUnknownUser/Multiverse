import {
  BadRequestException,
  Inject,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';

export interface TextGenerationInput {
  // Instructions belong to the backend feature, never to an untrusted client.
  instructions: string;
  input: string;
}

@Injectable()
export class OpenAIService {
  private client?: OpenAI;

  constructor(@Inject(ConfigService) private readonly config: ConfigService) {}

  async generateText({ instructions, input }: TextGenerationInput) {
    if (
      typeof input !== 'string' ||
      !input.trim() ||
      input.length > 12_000 ||
      typeof instructions !== 'string' ||
      !instructions.trim() ||
      instructions.length > 4_000
    )
      throw new BadRequestException({ code: 'AI_INVALID_INPUT' });

    const apiKey = this.config.get<string>('OPENAI_API_KEY');
    if (!apiKey)
      throw new ServiceUnavailableException({ code: 'AI_NOT_CONFIGURED' });

    try {
      this.client ??= new OpenAI({ apiKey, timeout: 20_000, maxRetries: 0 });
      const response = await this.client.responses.create({
        model: this.config.get<string>('OPENAI_MODEL') ?? 'gpt-4.1-mini',
        instructions,
        input,
        max_output_tokens: 1024,
        store: false,
      });
      // Never treat truncated, refused or empty output as a successful result.
      if (response.status !== 'completed' || !response.output_text?.trim()) {
        throw new Error('No complete text response');
      }
      return {
        text: response.output_text,
        usage: response.usage
          ? {
              inputTokens: response.usage.input_tokens,
              outputTokens: response.usage.output_tokens,
            }
          : null,
      };
    } catch {
      // Provider errors can include request data. Do not log or forward them.
      throw new ServiceUnavailableException({ code: 'AI_UNAVAILABLE' });
    }
  }
}
