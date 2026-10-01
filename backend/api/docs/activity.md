# Diário e avaliações

`GET /api/v1/me/activity` restaura o diário e as reviews da conta autenticada pelo
Firebase. `PUT /api/v1/me/diary/:id` grava um registro; `id` é um UUID v4 criado no
aparelho e preservado durante tentativas. O corpo aceita `itemId`, `loggedAt` em ISO
8601 com fuso, `rating` (0 a 5, passos de 0,5), `liked`, `rewatch`, `spoiler` e
`text` (até 5.000 caracteres). Zero significa sem nota. Identidade vem do token,
nunca do corpo. Perfil ativo é obrigatório.

Diário e review são gravados numa única transação. Texto ou nota cria uma review;
registro sem ambos continua válido no diário. Reenviar o mesmo UUID atualiza o
mesmo registro, sem duplicar a publicação após timeout. Um novo UUID registra
uma releitura/revisita. Uma tentativa idêntica não altera a prioridade da nota.
A média considera a última avaliação positiva de cada pessoa por obra; repetir
registros não multiplica seu peso. Contagens excluem contas em exclusão. Excluir
a conta remove seus registros e reviews por cascata.

Ambas as rotas retornam `{ entries, reviews, items, universes, followerCount }`.
As referências incluem itens arquivados para preservar o histórico. Novos registros
em obras arquivadas retornam 409 `ITEM_UNAVAILABLE`. Datas ficam em UTC; o app
agrupa e apresenta no calendário/fuso local. Metadados seguem `Accept-Language`
PT/EN; texto escrito pelo usuário não é traduzido. Sem registros retorna 200 com
listas vazias. Dados inválidos: 400 `INVALID_LOG`; data futura além de cinco minutos:
400 `INVALID_LOG_DATE`. Falhas não descartam o rascunho.

O iOS só fecha a publicação após confirmar o UUID na resposta. Bloqueia envios
simultâneos e preserva UUID/data/texto ao tentar novamente. A tela de diário vazia
convida ao primeiro registro; falha de carregamento oferece tentar novamente.
Os componentes visuais existentes são mantidos.

Esta etapa lê a atividade da própria conta, sem paginação. Feed de outras pessoas,
comentários, curtidas sociais e listas ainda usam os módulos anteriores. Não há
interface de edição/exclusão individual nesta entrega. Paginação e feed social
são etapas posteriores, antes de ampliar o volume de usuários.

A migration `005_diary_reviews.sql` deve preceder o deploy. Testes HTTP usam schema
PostgreSQL isolado e cobrem isolamento por conta, concorrência, retry, transações,
arquivamento, validações e exclusão da conta. Testes iOS cobrem restauração,
erros/retry, confirmação de publicação e decodificação das datas do PostgreSQL.
