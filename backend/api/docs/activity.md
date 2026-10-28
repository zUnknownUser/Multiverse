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

GET, PUT e PATCH retornam `{ entries, reviews, items, universes, followerCount }`.
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

Estas rotas operam sobre a atividade da própria conta. O contrato original sem query retorna snapshot completo; a paginação aditiva está descrita abaixo. O [feed social](social-feed.md)
tem paginação e regras próprias de publicação, privacidade e bloqueio. Comentários e reações têm [contrato próprio](interactions.md). O botão de curtir
obra fora do registro, a lista de desejos e listas continuam nos módulos anteriores.
O menu de cada registro no diário oferece edição e exclusão; o formulário atual
reabre com os dados daquele UUID, incluindo o texto original e a data. Exclusão
exige confirmação e só altera a tela após um recibo válido. Falhas preservam o
registro e oferecem retry. Puxar para atualizar com exclusão já confirmada e
pendente repete essa mesma ação para recuperar também as estatísticas da obra.
O progresso derivado do diário é recalculado; marcações
manuais de visto do onboarding permanecem independentes. O contrato paginado do diário pessoal está descrito abaixo.

As migrations `005_diary_reviews.sql` e `009_rating_histogram.sql` devem preceder o deploy. Testes HTTP usam schema
PostgreSQL isolado e cobrem isolamento por conta, concorrência, retry, transações,
arquivamento, validações e exclusão da conta. Testes iOS cobrem restauração,
erros/retry, confirmação de publicação e decodificação das datas do PostgreSQL.

Para validar manualmente: busque uma obra, registre nota/texto e marque Curti;
confira detalhes, diário, contagem, favorito e review no perfil. Reabra o app e
confirme o histórico. Sem conexão, tente atualizar e confira que o histórico
permanece; restabeleça a conexão e tente novamente. Entre em outra conta para
validar seu estado vazio. Repita em inglês. Um salvamento sem confirmação mantém o rascunho privado no aparelho, incluindo
UUID/data para repetir após reinício sem duplicar. Não há envio automático em segundo plano.

## Edição e exclusão individual (lote L04)

- `PATCH /api/v1/me/diary/:id` recebe o mesmo corpo completo do PUT, exige um
  registro existente da própria conta e mantém UUID, obra e identidade da review.
  Nota, texto, data, Curti, Revisitei e spoiler podem mudar. Obras arquivadas
  continuam editáveis no histórico pessoal Marvel/DC. UUID ausente/de outra conta:
  404 `LOG_NOT_FOUND`; trocar a obra: 409 `LOG_ITEM_CONFLICT`.
- `DELETE /api/v1/me/diary/:id` retorna `{ id, state }`, onde `state` é o snapshot
  de atividade já atualizado. Remove registro, review e interações em transação.
  Repetir uma exclusão confirmada retorna 200 com estado atual; ID nunca existente
  na própria conta retorna 404 `LOG_NOT_FOUND`, sem revelar dados de terceiros.
- A migration `028_diary_entry_deletions.sql` conserva somente dono/UUID/obra/data
  da exclusão, sem texto. O mesmo UUID não pode ser recriado por PUT/PATCH atrasado
  (409 `LOG_DELETED`). Os marcadores somem junto com a conta. Nova revisita usa
  outro UUID. Mutações seguem a trava transacional por conta já existente.
- Reviews do snapshot de atividade incluem `entryId`. A resposta de exclusão
  inclui a obra afetada e suas estatísticas, mesmo após remover o último registro.
  Médias/histogramas continuam seguindo a última nota positiva por pessoa/obra.
  Escritas concorrentes no mesmo registro seguem a ordem de execução no servidor;
  exclusão prevalece sobre gravações atrasadas e não permite ressurreição.
- Publicar backend/migration antes do novo app. O contrato social permanece igual;
  o vínculo `entryId` é exigido no snapshot privado de atividade do novo cliente.

Validação manual do lote L04: no diário, abra o menu de um registro e edite nota,
data, texto e opções; confira que a contagem não aumenta e que outra revisita da
mesma obra não muda. Cancele uma edição e uma exclusão para confirmar que nada é
gravado. Exclua após confirmar e confira favoritos, progresso, médias e reviews;
repita depois de perder a conexão/resposta. Faça isso em PT-BR/EN e claro/Noir.
Um visto marcado manualmente pode continuar após excluir o último registro.
Não há sincronização instantânea entre aparelhos; recarregar a atividade busca
o estado confirmado no servidor. O rascunho é local e não sincroniza entre aparelhos.

## Cotas e recuperação — 25/10/2026

Migration 030 cria recibos de criação em `review_publications`, independentes de
reviews. Limite: 20 novas reviews por conta em janela móvel de uma hora, inclusive
diário privado (impede contornar o limite alternando visibilidade). Excluir ou
limpar texto/nota não devolve cota; recriar a review consome outra unidade. Editar
ou repetir uma review ainda existente não consome. Sem texto/nota não consome.
Admissão e publicação compartilham transação/trava de ciclo de vida; falha reverte
ambas. Recibos antigos são limpos na próxima criação e somem junto com a conta.
A migration conserva o consumo dos últimos 60 minutos. Excesso: 429
`PUBLICATION_LIMIT`; a janela vencida permite novas criações.

No iOS, um rascunho por conta/ambiente usa JSON atômico com proteção completa do
arquivo, nome derivado por SHA-256 e exclusão dos backups do aparelho. Fechar
preserva alterações; fechar edição sem alterações a descarta. Salvar confirmado,
descartar explicitamente e encerrar sessão removem o arquivo. Falha de gravação
local é mostrada, sem prometer recuperação. Outra obra não sobrescreve o rascunho.
A Home permite retomar; a seleção de obras oferece busca por título.

Diário e biblioteca permitem busca sem distinção de acentos/caixa. Diário combina
ano e status (curtidos, com nota, revisitados); biblioteca busca obras/listas.
A tela exibe blocos de 30 registros com pilhas lazy. Isso limita renderização,
**não pagina a API**: o snapshot completo segue necessário para estatísticas,
favoritos e progresso. Paginação de rede exige separar esses agregados antes de
limitar o histórico; permanece melhoria de capacidade E03.

## Paginação aditiva — 28/10/2026

`GET /me/activity?limit=30` aceita `after`, `search` (todas as palavras do título,
sem acentos/caixa), `selection` (`all`, `liked`, `rated`, `rewatched`), `year` e
`timeZone` IANA. Consultas de reviews também aceitam `selection=reviewed`, `itemId` e `universeId` (Marvel/DC), sem depender da página aberta no diário. Limite 1–100. Cursor opaco preserva microssegundos e desempate
por criação/UUID, vinculado à conta, idioma e filtros. Resposta adiciona
`nextCursor` e `summary` (total, reviewCount, averageRating, years, latestEntries, recentReviews, buckets, activeDays).
O resumo independe dos filtros/páginas; latestEntries contém só a última entrada
por obra para progresso/defaults/favoritos, sem textos ou metadados completos.
PUT/PATCH/DELETE também aceitam `limit=30`; uma edição antiga inclui o UUID
confirmado além da página, no máximo 31 registros. Cliente reinicia a navegação
após mutações. Sem query mantém o contrato completo, inclusive exportação.
Paginação reflete dados atuais; edições concorrentes requerem atualizar o diário.

O resumo inclui as quatro reviews mais recentes, totais por ano/tipo/universo e
dias ativos dos últimos 105 dias no fuso solicitado. Metadados incluem referências
da página, favoritos e reviews recentes; arquivo histórico continua acessível.
Detalhes de obra/universo consultam até cinco reviews próprias independentemente
do diário. Exportação explícita usa o contrato completo; não exporta só a página.
O resumo cresce por obras distintas/anos, não por cada revisita; não é um snapshot
de todas as reviews. Não houve migration nem criação de serviço neste lote.
