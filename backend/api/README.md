# Multiverse API

API NestJS 12 + TypeScript com Firebase Authentication e PostgreSQL. Persiste conta,
onboarding, catálogo, diário, reviews, follows, posts, comentários, reações, notificações, biblioteca privada e proteções
sociais. Não armazena senhas nem emite tokens próprios.

Contrato novo e ativação futura de APNs: [comunidade e notificações](docs/community-notifications.md).
Push permanece desligado por padrão; a central funciona sem Apple Developer.

Biblioteca: [contrato, limites e migração](docs/library.md).

## Executar localmente

Use Node.js 24 LTS (24.15+) ou 26 e Docker:

```sh
cd backend/api
npm ci
cp -n .env.example .env
# Escolha POSTGRES_PASSWORD e ajuste a mesma senha em DATABASE_URL.
docker compose up -d --wait
npm run db:migrate
npm run start:dev
```

O exemplo local usa `APP_ENV=local`, Firebase `demo-multiverse-local` e Auth
emulator em `127.0.0.1:9099`, sem credenciais reais. Iniciar o emulador conforme
[guia de ambientes](../../docs/ENVIRONMENTS.md). O banco local usa a porta 55432 e
volume próprio; não reutilizar um banco de produção ou o volume legado.

Em staging/produção, a API usa Application Default Credentials: em ambiente Google, use a identidade
do serviço; no desenvolvimento, use ADC ou `GOOGLE_APPLICATION_CREDENTIALS`
apontando para um arquivo de conta de serviço **fora do repositório**, com acesso
ao Firebase Authentication do projeto. Nunca inclua essa credencial no app iOS.
O `GoogleService-Info.plist` é uma configuração cliente e não substitui a credencial
Admin. Não há credenciais Admin versionadas no repositório.

## Railway

Projeto: `multiverse` (`3d9b8511-b917-4a7a-8a7d-577853c8a011`), ambiente `production`.
Serviços: `api` e `Postgres`.
URL: `https://api-production-6e8d.up.railway.app/api/v1`.

O serviço está ligado ao GitHub `zUnknownUser/Multiverse`, branch `master`, raiz
`/backend/api`, com predeploy `npm run db:migrate` e healthcheck `/api/v1/health`.
O Dockerfile opcional compila com Node 24 e executa sem privilégios.
`.railway/railway.ts` conserva a preparação inicial de configuração via CLI;
não reaplique esse plano sem comparar com a configuração remota atual.
O template local agora usa `/api/v1/health/ready` para conferir PostgreSQL no
deploy futuro; o healthcheck remoto não foi alterado neste lote.
`DATABASE_URL` referencia `${{Postgres.DATABASE_URL}}` pela rede privada.
`FIREBASE_SERVICE_ACCOUNT_JSON` contém o JSON Admin somente nas variáveis do serviço;
o projeto da credencial precisa coincidir com `FIREBASE_PROJECT_ID`.

**Atenção ao lote L06:** o migrador agora exige `APP_ENV` e `FIREBASE_PROJECT_ID`
explícitos. Antes de qualquer publicação em produção, configurar `APP_ENV=production`.
A migration 029 identifica o banco; a API recusa inicialização em banco de outro
ambiente. Homologação continua pendente no Railway após a indisponibilidade de
21/10. Não usar push em master para experimentar staging.

O fluxo de produção é commit/push e acompanhamento do deploy GitHub no Railway.
Como alternativa operacional, a partir de `backend/api`:

```sh
railway link --project 3d9b8511-b917-4a7a-8a7d-577853c8a011
railway up . --path-as-root --service api --environment production --detach
```

Confira o commit/status atual no Railway; não publique o mesmo lote por CLI enquanto houver autodeploy em andamento. Não copie credenciais para o Dockerfile, código ou app iOS. Para atualizar
o segredo, use `railway variable set FIREBASE_SERVICE_ACCOUNT_JSON --stdin --service api`
com o conteúdo do arquivo local via stdin, sem imprimi-lo.

```sh
curl http://localhost:3000/api/v1/health
curl http://localhost:3000/api/v1/health/ready
```

A resposta local `{"status":"ok","service":"multiverse-api","environment":"local"}`
identifica o processo. `/health/ready` retorna 200 com `status=ready` somente se o
pool acessar PostgreSQL e confirmar a identidade do ambiente; indisponibilidade,
timeout ou identidade divergente retornam 503 com `status=unavailable`.
As duas rotas são públicas e usam `Cache-Control: no-store`. A prontidão tem cache
interno de até 5 segundos e prazo de resposta de 2 segundos, sem chamar provedores
externos. O header
`X-Multiverse-Environment` aparece nas respostas. Divergência enviada por um
cliente retorna 409 com `ENVIRONMENT_MISMATCH` antes das rotas.

Diagnóstico privado: após `npm run build`, `npm run ops:report` lê somente
contagens/idades das pendências de exclusão de conta, push e voz. Exige
`OPERATIONS_DATABASE_URL`, `APP_ENV` e `FIREBASE_PROJECT_ID` explícitos, sem carregar
`.env` nem reutilizar `DATABASE_URL`. Não retorna dados pessoais e não reprocessa
trabalhos. Contrato, códigos de saída e limites em [operação](docs/operations.md).

## Ambiente

| Variável                         | Uso                                                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| `APP_ENV`                        | `local`, `test`, `staging` ou `production`; ver [matriz](../../docs/ENVIRONMENTS.md) |
| `NODE_ENV`                       | `development` (padrão), `test` ou `production`                                       |
| `PORT`                           | `3000` por padrão                                                                    |
| `DATABASE_URL`                   | URL PostgreSQL usada pela API e pelo migrador                                        |
| `POSTGRES_PASSWORD`              | Senha do PostgreSQL local no Docker Compose                                          |
| `FIREBASE_PROJECT_ID`            | `demo-multiverse-local` local; projetos distintos em staging/produção                |
| `GOOGLE_APPLICATION_CREDENTIALS` | Caminho externo ao Git, quando não houver outra fonte de ADC                         |
| `TEST_DATABASE_URL`              | Banco descartável para executar os testes com PostgreSQL real                        |

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
| GET    | `/me/onboarding/suggestions`             | `{users, minimumFollows, followingOptional}`         |
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
valida IDs contra o catálogo publicado no PostgreSQL; não há lista fixa de IDs
no código de validação.

Sugestões incluem até 20 contas reais com onboarding concluído, excluindo o próprio
usuário e contas em exclusão. O `GET /me` também filtra os follows restaurados por
essa elegibilidade, preservando a ordem e a versão do progresso. Assim, uma exclusão
pendente no Firebase não obriga o app a reenviar uma seleção inválida repetidamente;
a leitura não altera o banco, e a próxima gravação versionada reconcilia a seleção.
Nesta etapa, elegibilidade significa conta que concluiu onboarding, não um selo de
especialista. **Seguir é opcional**: `followingOptional: true` permite concluir com
zero, uma ou mais pessoas. O campo legado `minimumFollows = min(3, disponíveis)`
permanece para que versões antigas continuem lendo sugestões; não é uma exigência
para salvar no servidor. O iOS atual exibe “Pular por enquanto” quando não há
seleções e “Montar meu feed” quando há. Zero candidatos ainda pula a etapa inteira.
Não são criados perfis fictícios. Perfis selecionados inelegíveis continuam gerando
conflito; escolher não seguir ninguém não depende de nova consulta de sugestões.
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
npm run check:local    # Verificação completa com PostgreSQL temporário (Docker)
npm run test:local     # Unitários e HTTP com PostgreSQL temporário (Docker)
npm run check          # Verificação completa; exige TEST_DATABASE_URL
npm run start:dev      # Servidor com recarga
npm run build
npm run start:prod     # Defina NODE_ENV=production no ambiente
npm run db:migrate
```

Os comandos `check:local` e `test:local` criam um PostgreSQL 18 descartável com
porta aleatória em localhost e removem o container ao terminar. Não usam o banco
do Compose nem uma URL de banco herdada. Docker precisa estar em execução.

Para usar um banco de testes já preparado, configure `TEST_DATABASE_URL` antes de
executar `npm run check` ou `npm run test:e2e`. Cada suíte cria um schema aleatório,
aplica todas as migrations e apaga somente seu schema ao terminar. A execução é
serial, com até 60 segundos por hook. Ausência da URL, URL inválida ou banco
inacessível fazem a etapa falhar, em vez de ignorar suítes de persistência.
Use exclusivamente banco de testes com permissão de criar schemas.

`npm test` executa somente os unitários. O setup de testes remove a URL da aplicação
e credenciais externas herdadas, força ambiente de teste e desliga push/voz.
Consulte o [guia de testes e CI](../../docs/TESTING.md) para os comandos da raiz,
versões dos runtimes e limites desta validação.

Os testes HTTP usam o banco real e um verificador Firebase injetado: cobrem
isolamento de contas, validação, concorrência de username/progresso, disponibilidade
de pessoas e exclusão interrompida. Não autenticam usuários Google reais nem
validam permissões da credencial Admin do ambiente.

## Escopo e próximas etapas

O iOS usa clientes separados por contrato para conta, [catálogo](docs/catalog.md),
[diário](docs/activity.md), [pessoas](docs/people.md), [feed](docs/social-feed.md) e
[comentários/reações](docs/interactions.md). A CLI de moderação revisa denúncias com
conexão administrativa privada e auditoria. Clubes, mensagens, salas e outros
módulos ainda usam demonstração. Ajustes não migrados continuam locais por UID.

As funções de e-mail em `../firebase` já têm registro de publicação. O teste
integrado com contas reais segue pendente. Ainda faltam monitoramento com alertas,
readiness de dependências e limites gerais de produção para lançamento.
Veja o [resumo de retomada](../../docs/SESSION_HANDOFF.md).

Referências: [NestJS](https://docs.nestjs.com/),
[Firebase: verificar ID tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[node-postgres: transações](https://node-postgres.com/features/transactions).

### Duelo do Dia

Migration `024_daily_duels.sql` vincula rodadas editoriais aos posts existentes.
`GET /community/daily-duels` retorna rodada atual/anterior, horário do servidor e
progresso; `GET /community/daily-duels/:uuid` abre convite/resultado; `GET
/community/daily-duels/leaderboard` retorna mês, top 30 e posição própria.
Autenticação e onboarding são obrigatórios; respostas são `no-store`.
`Accept-Language` escolhe conteúdo editorial PT-BR/EN, inclusive `/posts` e busca.
Voto usa o endpoint existente `/posts/:uuid/vote` e sua idempotência/deadline.
Pontuação deriva dos votos únicos dentro da janela: 10 por rodada, mês UTC;
comentários/convites não pontuam. Ranking exclui deletados/moderados e oculta
bloqueados após calcular posições. Títulos são cumulativos de participação.
A migração 027 substitui o rodízio fixo por uma fila editorial no banco, com 40
perguntas iniciais inéditas, agendamento e sugestões da comunidade revisadas em
PT-BR/EN. Conteúdo é consumido uma vez, sem repetição automática. Operação privada,
fluxos e limites: [curadoria dos duelos](docs/daily-duels.md).
O primeiro acesso cria o post e o perfil editorial explícito sob lock; não gera
votos, participantes, mensagens ou alertas falsos. Detalhes em SESSION_HANDOFF.
