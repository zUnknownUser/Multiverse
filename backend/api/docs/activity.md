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
A média e o histograma consideram a última avaliação positiva de cada pessoa por
obra; repetir registros não multiplica seu peso. `ratingHistogram` contém dez
contagens, de 0,5 a 5 estrelas, nas respostas de catálogo, detalhes e atividade.
Sem avaliações, todas são zero; o app mostra ausência de notas. Contagens excluem contas em exclusão. Excluir
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

Diário e perfil aceitam puxar para atualizar. A falha dessa atualização mantém o
último histórico carregado e oferece nova tentativa na própria tela; uma resposta
iniciada antes de um salvamento não pode desfazer o registro confirmado. Um erro
de data futura permite tentar novamente com o relógio corrigido, sem perder o
texto nem o UUID. A confirmação verifica também obra, nota, data e opções enviadas.

O perfil apresenta até quatro favoritos derivados de `liked` no registro mais
recente de cada obra, sem repetir obras revisitadas. Reviews e favoritos de
exemplo não são apresentados como atividade real. A seção de reviews da obra
identifica explicitamente as reviews da própria conta; avaliações sem texto têm
uma descrição localizada. Tocar repetidamente na mesma estrela permite nota
inteira, meia estrela e sem nota. Novos estados e mensagens têm PT-BR e inglês.

Estas rotas leem a atividade da própria conta, sem paginação. O [feed social](social-feed.md)
tem paginação e regras próprias de publicação, privacidade e bloqueio. Comentários, curtidas sociais, o botão de curtir
obra fora do registro, a lista de desejos e listas continuam nos módulos anteriores.
Não há
interface de edição/exclusão individual nesta entrega. A paginação do diário
pessoal ainda é uma etapa posterior, antes de ampliar o volume de usuários.

As migrations `005_diary_reviews.sql` e `009_rating_histogram.sql` devem preceder o deploy. Testes HTTP usam schema
PostgreSQL isolado e cobrem isolamento por conta, concorrência, retry, transações,
arquivamento, validações e exclusão da conta. Testes iOS cobrem restauração,
erros/retry, confirmação de publicação e decodificação das datas do PostgreSQL.

Para validar manualmente: busque uma obra, registre nota/texto e marque Curti;
confira detalhes, diário, contagem, favorito e review no perfil. Reabra o app e
confirme o histórico. Sem conexão, tente atualizar e confira que o histórico
permanece; restabeleça a conexão e tente novamente. Entre em outra conta para
validar seu estado vazio. Repita em inglês. Um salvamento sem confirmação mantém
o rascunho na sheet, mas não há armazenamento offline do rascunho entre reinícios.
