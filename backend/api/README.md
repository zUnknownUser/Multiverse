# Multiverse API

API NestJS 12 + TypeScript com Firebase Authentication e PostgreSQL. A primeira
etapa persiste perfil, reserva de @usuário, progresso do onboarding e os follows
feitos durante esse fluxo. Não armazena senhas nem emite tokens próprios.

## Executar localmente

Use Node.js 24 LTS (24.15+) ou 26 e Docker:

```sh
cd backend/api
npm ci
cp .env.example .env
# Escolha POSTGRES_PASSWORD e ajuste a mesma senha em DATABASE_URL.
docker compose up -d --wait
npm run db:migrate
npm run start:dev
```

Configure também as credenciais Firebase Admin antes de usar as rotas de conta.
A API usa Application Default Credentials: em ambiente Google, use a identidade
do serviço; no desenvolvimento, use ADC ou `GOOGLE_APPLICATION_CREDENTIALS`
apontando para um arquivo de conta de serviço **fora do repositório**, com acesso
ao Firebase Authentication do projeto. Nunca inclua essa credencial no app iOS.
O `GoogleService-Info.plist` é uma configuração cliente e não substitui a credencial
Admin. Não há credenciais Admin incluídas nesta entrega.

```sh
curl http://localhost:3000/api/v1/health
```

A resposta `{"status":"ok","service":"multiverse-api"}` é uma verificação de
vida do processo; não atesta conectividade com PostgreSQL ou Firebase.

## Ambiente

| Variável                         | Uso                                                           |
| -------------------------------- | ------------------------------------------------------------- |
| `NODE_ENV`                       | `development` (padrão), `test` ou `production`                |
| `PORT`                           | `3000` por padrão                                             |
| `DATABASE_URL`                   | URL PostgreSQL usada pela API e pelo migrador                 |
| `POSTGRES_PASSWORD`              | Senha do PostgreSQL local no Docker Compose                   |
| `FIREBASE_PROJECT_ID`            | `multiverse-7f87c` no desenvolvimento; explícito em produção  |
| `GOOGLE_APPLICATION_CREDENTIALS` | Caminho externo ao Git, quando não houver outra fonte de ADC  |
| `TEST_DATABASE_URL`              | Banco descartável para executar os testes com PostgreSQL real |

Variáveis do processo têm prioridade sobre `.env`. Os testes da aplicação ignoram
`.env`. Em produção, URL do banco e ID do projeto são obrigatórios, e o emulador
Auth é rejeitado. Sem banco no desenvolvimento, health continua acessível, mas
as operações de conta retornam 503. Use HTTPS na hospedagem e a configuração TLS
do provedor de PostgreSQL na connection string, sem desabilitar a validação do certificado.

## Contrato inicial

Todas as rotas abaixo têm prefixo `/api/v1`, exigem
`Authorization: Bearer <Firebase ID token>` e usam exclusivamente o UID verificado
do token como identidade. O Admin SDK verifica assinatura, expiração, projeto,
revogação e conta desativada. E-mail precisa estar confirmado; anônimos são rejeitados.

| Método | Rota                                     | Resultado                                            |
| ------ | ---------------------------------------- | ---------------------------------------------------- |
| GET    | `/me`                                    | `{profile, onboarding}`; perfil ausente é `null`     |
| GET    | `/me/username-availability?username=...` | `{available: boolean}`                               |
| PUT    | `/me/profile`                            | Salva e retorna o perfil                             |
| GET    | `/me/onboarding/suggestions`             | `{users, minimumFollows}`                            |
| PUT    | `/me/onboarding`                         | Salva e retorna o progresso com versão incrementada  |
| DELETE | `/me`                                    | Remove conta Firebase e dados de conta no PostgreSQL |

Perfil: `userID`, `username`, `displayName`, `avatarColor`, `bio`, `createdAt`,
`updatedAt`. Para salvar, envie somente `username`, `displayName`, `avatarColor`,
`bio`. O username é normalizado para minúsculas, tem 3–24 caracteres (`a-z`,
`0-9`, `_`, `.`), e é único por constraint no banco, inclusive em requisições
simultâneas. Consultar disponibilidade não reserva o nome; o PUT pode retornar
409 `USERNAME_TAKEN`. Nome tem 1–80 caracteres, bio até 160 e cor é `#RRGGBB`.

Exemplo de progresso:

```json
{
  "universeIDs": ["wow"],
  "seenItemIDs": ["w-wotlk"],
  "followedUserIDs": [],
  "step": 2,
  "completed": false,
  "version": 0
}
```

A versão começa em zero; cada escrita incrementa e retorna a versão. Enviar uma
versão antiga retorna 409 `STALE_ONBOARDING`: recarregue `/me` antes de editar de
novo. Etapa maior que 1 ou conclusão exige pelo menos um universo. O servidor
valida IDs contra o catálogo atual do app em `src/accounts/catalog-ids.ts`.
Esse catálogo ainda é estático: sua migração para o banco é uma próxima etapa.

Sugestões incluem até 20 contas reais com onboarding concluído, excluindo o próprio
usuário e contas em exclusão. O `GET /me` também filtra os follows restaurados por
essa elegibilidade, preservando a ordem e a versão do progresso. Assim, uma exclusão
pendente no Firebase não obriga o app a reenviar uma seleção inválida repetidamente;
a leitura não altera o banco, e a próxima gravação versionada reconcilia a seleção.
Nesta etapa, elegibilidade significa conta que
concluiu onboarding, não um selo de especialista. O mínimo é `min(3, disponíveis)`:
zero pula a etapa no iOS, uma exige uma, duas exigem duas e três ou mais exigem
três. Não são criados perfis fictícios para preencher a lista. Mudanças na comunidade
entre a consulta e a conclusão retornam conflito; o app oferece recarregar.
Follows e progresso são salvos na mesma transação; conclusão não pode voltar a rascunho.
As transações mantêm os perfis protegidos por travas compartilhadas e serializam a
escrita na linha de progresso. Isso evita travas exclusivas cruzadas quando duas
pessoas que se seguem salvam simultaneamente. Uma conexão cujo rollback falhar é
descartada, para não reutilizar uma transação em estado indefinido.

Exclusão exige autenticação recente (até cinco minutos). Uma marca persistente
oculta a conta antes da remoção no Firebase. Se houver falha, o serviço tenta
reconciliar a cada minuto enquanto a API estiver em execução. Dados relacionados
são removidos por cascata e referências do onboarding de outros usuários são
atualizadas. Não há job dependente de memória para guardar a intenção de exclusão.
`AccountLifecycleService` isola essa coordenação das regras de perfil/onboarding.
A migration `002_account_deletions.sql` preserva exclusões interrompidas anteriores e
registra a intenção mesmo para uma conta que ainda não criou perfil. Após a remoção,
a tabela `account_deletions` mantém somente UID e datas de pedido, tentativa e conclusão, sem nome,
bio ou username, impedindo que requisições já autenticadas recriem o perfil apagado.
Criação/atualização de perfil e exclusão usam a mesma trava de transação por UID.
A migration `003_deletion_retry_fairness.sql` registra a última tentativa de exclusão.
O reconciliador prioriza pedidos ainda não tentados e depois os tentados há mais tempo,
para que um lote com falhas persistentes não impeça o processamento de novos pedidos.

Erros usam status HTTP e `code`, sem depender do idioma do cliente. O iOS traduz
as mensagens em PT-BR/EN. Campos desconhecidos e payloads inválidos são rejeitados.

## Banco e migrations

`migrations/001_accounts.sql` cria `profiles`, `onboarding` e `follows`.
`npm run db:migrate` usa transações, trava para impedir execução simultânea e
checksums para detectar alterações em migrations já aplicadas. Adicione novas
migrations; não edite as já aplicadas. A API não executa migrations automaticamente.
O Compose expõe somente `127.0.0.1:5432` e preserva dados no volume `postgres_data`.
`docker compose down` para o banco sem apagar esse volume.

## Testes e comandos

```sh
npm run check          # Formatação, lint, tipos, build, unitários e HTTP
npm run start:dev      # Servidor com recarga
npm run build
npm run start:prod     # Defina NODE_ENV=production no ambiente
npm run db:migrate
```

Para incluir os testes de persistência, configure `TEST_DATABASE_URL` apontando
para um PostgreSQL de testes antes de executar `npm run check`. A suíte cria um
schema aleatório, executa a migration nele e apaga somente esse schema ao terminar.
Sem essa variável, os testes de PostgreSQL são explicitamente ignorados. Use
exclusivamente um banco de desenvolvimento/testes, com permissão de criar schemas.

Os testes HTTP usam o banco real e um verificador Firebase injetado: cobrem
isolamento de contas, validação, concorrência de username/progresso, disponibilidade
de pessoas e exclusão interrompida. Não autenticam usuários Google reais nem
validam permissões da credencial Admin do ambiente.

## Escopo e próximas etapas

O iOS usa `AccountAPIClient` para esta integração. Catálogo, feed, reviews, diário,
clubes, mensagens, follows fora do onboarding e outros recursos ainda usam o
repositório de demonstração. Ajustes de conta continuam locais por UID.
As funções de código por e-mail em `../firebase` seguem independentes e precisam
ser ativadas conforme seu próprio guia. Ainda não há deploy da API, banco hospedado,
monitoramento, readiness de dependências ou política de rate limiting de produção.

Referências: [NestJS](https://docs.nestjs.com/),
[Firebase: verificar ID tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[node-postgres: transações](https://node-postgres.com/features/transactions).
