# Multiverse API

Base da API em NestJS 12 + TypeScript, gerada com a CLI oficial. Usa Express,
ES modules, npm e dependências fixadas no `package-lock.json`.

## Desenvolvimento

Use Node.js 24 LTS (24.15 ou superior). Com nvm:

```sh
cd backend/api
nvm install
nvm use
npm ci
npm run start:dev
```

Também é compatível com Node.js 26, usado na validação inicial deste projeto.
Na raiz do monorepo, os atalhos são `make api-install` e `make api-dev`.

A API inicia em `http://localhost:3000`. Para verificar:

```sh
curl http://localhost:3000/api/v1/health
```

Resposta: `{"status":"ok","service":"multiverse-api"}`. Essa rota verifica
somente que o servidor responde; ainda não há dependências externas para testar.

## Ambiente

O `.env` é opcional no desenvolvimento. Para personalizar, copie `.env.example`
para `.env`. Nunca versione segredos.

| Variável   | Padrão        | Valores                             |
| ---------- | ------------- | ----------------------------------- |
| `NODE_ENV` | `development` | `development`, `test`, `production` |
| `PORT`     | `3000`        | Inteiro de 1 a 65535                |

Variáveis do processo têm prioridade sobre o `.env`. Configurações inválidas
impedem a inicialização. Testes ignoram o `.env` local.

## Comandos

```sh
npm run start:dev     # Reinicia ao editar código
npm run build        # Gera dist/
npm run start:prod   # Executa o build; defina NODE_ENV=production no ambiente
npm run check        # Formatação, lint, tipos, build, testes unitários e HTTP
npm run format       # Aplica Prettier
```

Oxlint faz o lint; Vitest executa os testes; Supertest verifica as rotas HTTP.

## Estrutura

```text
src/
├── main.ts              # Inicialização e porta
├── app.module.ts        # Módulo raiz
├── configure-app.ts     # Prefixo /api/v1, Helmet, validação e shutdown
├── config/              # Leitura e validação de ambiente
└── health/              # GET /api/v1/health
test/                    # Testes HTTP da aplicação
```

Os próximos recursos devem ser organizados por módulo. O pipe global está pronto
para validar DTOs com `class-validator`, transformar payloads e rejeitar campos
não declarados. Helmet configura cabeçalhos HTTP. CORS não está habilitado;
o cliente iOS nativo não exige CORS, e origens web serão definidas quando necessário.

Esta entrega é somente a base executável. Banco, ORM, autenticação Firebase na API,
endpoints de negócio e hospedagem ainda serão definidos. Não há deploy configurado.
O app iOS continua usando sua integração existente; as funções de verificação
em `../firebase` continuam independentes e não foram migradas para esta API.

Referências: [NestJS](https://docs.nestjs.com/first-steps),
[configuração](https://docs.nestjs.com/techniques/configuration) e
[validação](https://docs.nestjs.com/techniques/validation).
