import { ConfigService } from '@nestjs/config';
import { OpenAIService } from './openai.service.js';

const sdk = vi.hoisted(() => ({ create: vi.fn(), options: vi.fn() }));
vi.mock('openai', () => ({
  default: class {
    responses = { create: sdk.create };
    constructor(options: unknown) {
      sdk.options(options);
    }
  },
}));

describe('OpenAI integration', () => {
  const input = {
    instructions: 'Summarize the supplied text.',
    input: 'Example text.',
  };
  const service = (
    config = {
      OPENAI_API_KEY: 'test-only-placeholder',
      OPENAI_MODEL: 'configured-model',
    },
  ) => new OpenAIService(new ConfigService(config));

  beforeEach(() => vi.resetAllMocks());

  it('bounds calls, disables storage and retries, and returns text and usage', async () => {
    sdk.create.mockResolvedValue({
      status: 'completed',
      output_text: 'Summary',
      usage: { input_tokens: 12, output_tokens: 3 },
    });
    await expect(service().generateText(input)).resolves.toEqual({
      text: 'Summary',
      usage: { inputTokens: 12, outputTokens: 3 },
    });
    expect(sdk.options).toHaveBeenCalledWith({
      apiKey: 'test-only-placeholder',
      timeout: 20_000,
      maxRetries: 0,
    });
    expect(sdk.create).toHaveBeenCalledWith({
      ...input,
      model: 'configured-model',
      max_output_tokens: 1024,
      store: false,
    });
  });

  it('can initialize without a key and fails only when generation is requested', async () => {
    const ai = service({
      OPENAI_API_KEY: '',
      OPENAI_MODEL: 'configured-model',
    });
    await expect(ai.generateText(input)).rejects.toMatchObject({
      response: { code: 'AI_NOT_CONFIGURED' },
    });
    expect(sdk.create).not.toHaveBeenCalled();
  });

  it.each([
    { ...input, input: ' ' },
    { ...input, input: 'x'.repeat(12_001) },
    { ...input, instructions: '' },
    { ...input, instructions: 'x'.repeat(4_001) },
  ])(
    'rejects invalid input before sending a provider request',
    async (request) => {
      await expect(service().generateText(request)).rejects.toMatchObject({
        response: { code: 'AI_INVALID_INPUT' },
      });
      expect(sdk.create).not.toHaveBeenCalled();
    },
  );

  it.each([
    { status: 'incomplete', output_text: 'Partial' },
    { status: 'completed', output_text: '' },
    { status: 'completed', output_text: '  ' },
  ])(
    'does not return incomplete or empty output as a success',
    async (response) => {
      sdk.create.mockResolvedValue(response);
      await expect(service().generateText(input)).rejects.toMatchObject({
        response: { code: 'AI_UNAVAILABLE' },
      });
    },
  );

  it('does not expose provider errors or retry failed calls', async () => {
    sdk.create.mockRejectedValue(
      new Error('private request and credential details'),
    );
    await expect(service().generateText(input)).rejects.toMatchObject({
      response: { code: 'AI_UNAVAILABLE' },
    });
    expect(sdk.create).toHaveBeenCalledTimes(1);
  });
});
