# OpenAI no backend

`AIModule` está registrado em `AppModule` e exporta `OpenAIService` para outros
módulos NestJS. A integração usa o SDK oficial e a Responses API:
https://developers.openai.com/api/docs/quickstart

`OPENAI_API_KEY` fica nas variáveis do serviço `api` no Railway. Para desenvolver
localmente, configure sua chave no `.env` ignorado pelo Git. Não copie a chave para
Swift, Info.plist, documentação ou testes. Para rotacionar, substitua a variável
no Railway e faça um novo deploy.

`OPENAI_MODEL` configura o modelo; o padrão inicial é `gpt-4.1-mini`.
A ausência da chave não impede login, perfil ou inicialização da API; somente
chamadas de IA falham com `AI_NOT_CONFIGURED`.

## Usar em uma funcionalidade

Importe `AIModule` no módulo da funcionalidade e injete `OpenAIService`:

```ts
const result = await this.openAI.generateText({
  instructions: 'Resuma o texto fornecido em português, sem acrescentar fatos.',
  input: text,
});
// result.text e result.usage: { inputTokens, outputTokens } | null
```

As instruções devem ser definidas pelo backend. O serviço aceita até 12 mil
caracteres de entrada e 4 mil de instruções, limita a saída a 1.024 tokens,
usa timeout de 20 segundos e desabilita retries automáticos. Solicita `store: false`
e não registra chave, prompts, respostas ou erros brutos do provedor. Isso não
substitui as políticas de retenção da OpenAI.

Respostas incompletas ou sem texto e falhas do provedor retornam `AI_UNAVAILABLE`;
entradas inválidas retornam `AI_INVALID_INPUT`. Os testes usam um SDK simulado e
não consomem créditos.

Esta etapa fornece a integração interna. Não há rota pública nem tela de IA.
Ao definir a primeira funcionalidade, implementar o contrato, autorização,
limites de uso por usuário e regras do produto antes de expor chamadas ao app.
