# Ordens de leitura editoriais

Migration `021_reading_orders.sql` transforma os percursos em conteúdo publicado no
PostgreSQL. Seguir/deixar de seguir, votar/remover voto e contagens são reais, por UID
Firebase. Nenhum voto, seguidor ou autor fictício foi importado do repositório demo.

## Experiência

Marvel ou DC → Ordens. Mesmos cartões, cores, tipografia e passos numerados do app.
Ordens seguidas aparecem primeiro; depois votos reais e ID para desempate estável.
O detalhe identifica a curadoria como Multiverse e explica o recorte. O botão de
próxima leitura abre a primeira obra ainda não registrada. Tocar no círculo de uma
obra não registrada abre o formulário existente do diário; tocar numa já registrada
abre a ficha. Não existe outro check de conclusão em paralelo ao diário.

Progresso usa IDs distintos das obras registradas no diário da conta. Releituras não
contam duas vezes. Checks antigos de onboarding/demo não concluem etapas. A leitura
de uma edição avulsa não conclui automaticamente a obra agregada; não inferimos que
um capítulo significa ler o volume inteiro. As ordens não fornecem páginas de HQ.

## Conteúdo inicial e revisão

Três seleções editoriais originais em PT-BR/EN, com obras já publicadas no catálogo:

- **Marvel: três grandes histórias:** Fênix Negra → Guerra Civil → Guerras Secretas
  (2015). Recorte em ordem de publicação, sem pretensão de ser uma cronologia completa.
- **DC: crises e recomeços:** Crise nas Infinitas Terras → Flashpoint. Não declara uma
  continuação direta; o texto informa que há outras histórias entre os dois eventos.
- **DC: outras visões dos heróis:** Watchmen → Reino do Amanhã. Sugestão de leitura
  de histórias independentes, sem inventar uma cronologia compartilhada.

Referências oficiais consultadas para identidade e contexto das obras em 03/10/2026:
[Dark Phoenix Saga](https://www.marvel.com/comics/issue/41624/x-men_dark_phoenix_saga_trade_paperback),
[eventos Marvel](https://www.marvel.com/comics/discover/1003/events-and-modern-classics),
[Secret Wars 2015](https://share.marvel.com/comics/discover/508/secret-wars),
[Crise nas Infinitas Terras](https://www.dc.com/graphic-novels/crisis-on-infinite-earths-1985/crisis-on-infinite-earths),
[Flashpoint](https://www.dc.com/graphic-novels/flashpoint-2011/flashpoint),
[Watchmen](https://www.dc.com/characters/watchmen) e
[Reino do Amanhã](https://www.dc.com/graphic-novels/kingdom-come-1996/kingdom-come).
As fontes sustentam as obras; a seleção e os textos são editoriais do Multiverse,
não listas oficiais reproduzidas. A fase inicial não inclui capítulos complementares
nem substitui uma futura curadoria por edições/personagens.

## Contrato e persistência

- `GET /api/v1/me/reading-orders`: `{version,locale,orders}`. Autenticado, conta ativa e
  onboarding concluído. `Accept-Language` PT-BR/EN; sem cache de dados de outra conta.
- `PUT /api/v1/me/reading-orders`: `{mutationID,version,orderID,action,enabled}`.
  `action` aceita `following` ou `voted`. Retorna `{mutationID,appliedVersion,state}`.
- Versionamento por conta rejeita alteração de dispositivo desatualizado (`ORDER_STALE`).
  UUID/payload idênticos confirmam a operação anterior e retornam estado atual; um
  retry antigo nunca ressuscita um follow removido depois. UUID com outro payload conflita.
- Até 120 alterações novas/hora por conta; retries confirmados não consomem orçamento.
  Exclusão de conta remove estado/recibos e seus votos/seguidores deixam as contagens.
- Tabelas editoriais: `reading_orders`, `reading_order_translations`, `reading_order_steps`.
  Privadas: `reading_order_state`, `reading_order_marks`, `reading_order_mutations`.
- Uma ordem só aparece quando publicada, com ambas as traduções e todas as obras
  publicadas como HQs do mesmo universo ativo Marvel/DC. Uma etapa arquivada oculta
  **a ordem inteira**, preservando marcações e sequência até revisão editorial.

Publicação editorial é administrativa: transação no banco/migration revisada, estado
`draft`, ambas as traduções, posições consecutivas sem duplicatas, referências de
catálogo e revisão do recorte, depois `published`. Não há endpoint público para editar
os percursos nem painel editorial nesta entrega. `archived` retira uma ordem sem apagar
marcações. Catálogo e ordens são lidos separadamente; obra ausente no cache iOS mostra
atualização necessária em vez de remover silenciosamente a etapa.

## Performance, limites e validação

Snapshot leve carregado ao abrir ordens/detalhe e ao voltar ao primeiro plano, sem
polling periódico ou dependência nova. Atualiza diário para progresso entre aparelhos.
Resposta de escrita atualiza o snapshot; erros preservam estado confirmado. Retry
incerto conserva UUID/payload e exibe ação de tentar novamente. Rascunho de operação
vive na sessão, não há fila offline durável após encerrar o app.

Testes HTTP/PostgreSQL cobrem localização, referências, zero contagens fictícias,
isolamento, votos/follows, idempotência, concorrência, versão desatualizada, arquivo,
tradução ausente, tipo/universo inválido, diário, exclusão e limites. Testes iOS cobrem
progresso único, checks legados, recibos inválidos, rede/cancelamento, resposta atrasada,
contagem sem soma local, isolamento e validação de payload.

QA manual: duas contas/dispositivos; seguir/votar/reverter e reabrir, registrar uma obra
no diário, reler sem duplicar progresso, testar PT-BR/EN e retry após queda de rede.
Ainda fora de escopo: criar ordens pela comunidade, comentários de ordem, edição pelo
app, equivalência automática volume↔edições, cronologia canônica completa e widget real.
