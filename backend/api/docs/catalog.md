# Catálogo inicial

`GET /api/v1/catalog` é uma leitura pública do PostgreSQL, sem dados pessoais.
`Accept-Language` seleciona `pt-BR` ou `en`, respeitando pesos `q`; idiomas não
suportados usam português. Uma tradução inglesa ausente usa a versão portuguesa
do registro. Resposta: `{ version: 1, locale, universes, comingSoon, items }`.
`version` identifica o contrato, não uma revisão editorial.

A migration `004_catalog.sql` cria universos, itens e suas traduções. Importa os
3 universos ativos, 3 futuros e 31 itens já existentes nos recursos PT/EN do app,
preservando IDs, ordem, textos e cores. É uma carga editorial inicial do protótipo,
não um catálogo completo nem uma integração com provedores externos. Alterações
futuras são feitas no banco por migrations novas; não edite migrations aplicadas.

## Publicação e onboarding

- Universos: `active`, `coming_soon` ou `archived`.
- Itens: `published` ou `archived`, sempre vinculados a um universo.
- Português é a tradução base necessária para publicação.
- Itens de universos não ativos não aparecem no catálogo.
- IDs existentes devem ser preservados; retire conteúdo usando `archived`.
- O onboarding valida universos e itens no banco, dentro da transação. Personagens
  não são aceitos como obras vistas. IDs indisponíveis retornam 409 `CATALOG_CHANGED`.
- Novos IDs não precisam ser acrescentados ao código de validação.

`total` é a quantidade publicada de itens. `members` conta perfis com onboarding
concluído que selecionaram o universo, excluindo contas em exclusão. Os números
fictícios de engajamento não foram importados. `base` e `live` retornam zero; presença ainda será implementada. `avg`,
`logCount` e `reviewCount` usam a atividade persistida (veja [diário](activity.md)). A leitura usa uma transação
com snapshot consistente para não misturar itens e totais de publicações distintas.

## iOS

`RootView` injeta `CatalogAPIClient` em `AppStore`. O catálogo remoto substitui os
universos e itens usados no onboarding, busca, cards e detalhes, mantendo os mesmos
modelos visuais. A lista “Em breve” também vem da API, incluindo League of Legends.
A carga ocorre ao preparar a sessão; reabra o app para obter alterações editoriais.

O loading aparece somente durante a consulta. Falta de internet, timeout e serviço
indisponível têm mensagens distintas e ações de tentar novamente ou sair, usando
fontes, cores e botão primário existentes. Ausência de universos é apresentada como
“Catálogo em preparação”, um estado informativo, e buscas vazias orientam mudar o
nome ou filtro sem exibir erro. Cancelamento de uma consulta não mostra falha.
Não substitui uma falha por catálogo fictício. A tentativa refaz a consulta; seleções retiradas do
catálogo são descartadas localmente ao restaurar o onboarding. Universo sem itens
continua válido. A busca filtra o snapshot carregado, sem paginação nesta primeira etapa.

Mocks continuam disponíveis para previews/testes. O diário e as reviews da própria
conta são persistidos. Feed social de outras pessoas, listas,
timelines, clubes e outros módulos ainda usam os dados anteriores nesta etapa.
O catálogo inicial não torna esses recursos persistentes nem seus contadores reais.

## Verificação

Testes HTTP com PostgreSQL isolado cobrem seed, PT/EN, fallback, publicação, novos
IDs e rejeição transacional sem modificar progresso salvo. Os testes iOS cobrem
decodificação, idioma, falha/retry sem fallback fictício, integridade referencial e
um catálogo com apenas um universo. A API deve ser publicada com a migration antes
de executar a nova versão do app. O predeploy do Railway executa `npm run db:migrate`.
