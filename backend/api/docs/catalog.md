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
fictícios de engajamento não foram importados. `base` e `live` retornam zero; presença de salas usa a API própria. `avg`,
`logCount` e `reviewCount` usam a atividade persistida (veja [diário](activity.md)). A leitura usa uma transação
com snapshot consistente para não misturar itens e totais de publicações distintas.

## iOS

`RootView` injeta `CatalogAPIClient`; `CatalogStore` possui a seleção inicial,
cache por ID, páginas, cursores e erros. `AppStore` coordena a sessão e mantém os
acessos usados pelas telas. Demos e previews continuam com o catálogo em memória.

A sessão real carrega `/catalog/bootstrap` (até 31 itens por universo), com
seleções explícitas para Home/onboarding/notas e totais do catálogo inteiro.
Busca, personagens, seletores de obras e edições carregam páginas de 30;
listas de séries usam páginas de 20. Séries preservam a ordem numérica das edições.
Os filtros e o idioma fazem parte do cursor; mudar a busca não mistura resultados.

Biblioteca, favoritos, percursos, salas, clubes e cartas resolvem os IDs usados
pela tela em lotes de até 50. Referências privadas do diário continuam vindo da
API de atividade. Um erro de rede permite tentar novamente; apenas `missingIDs`
confirma retirada do catálogo. Referências compartilhadas terminam de carregar
mesmo se a tela que iniciou a leitura fechar. Recarregar a conta invalida páginas
e respostas antigas. Essa cache é de sessão, sem persistência offline.

Progresso usa referências compactas de obras registradas/vistas e totais completos,
sem depender da página visível. O onboarding restaura seleções publicadas fora do
bootstrap e descarta apenas retiradas confirmadas; falha de leitura não apaga escolhas.
A média do catálogo também vem de agregação completa. Falhas nunca carregam fixtures
na conta real. Estados vazios, erros, loading e retry mantêm o design e as traduções.

As integrações sociais, biblioteca, clubes, salas e mensagens usam suas APIs
próprias. O catálogo fornece metadados; a situação de lançamento de cada módulo é
registrada em [LAUNCH_READINESS](../../../docs/LAUNCH_READINESS.md).

## Disponibilidade no início do lançamento

O fluxo legado pede `min(3, loristas elegíveis)`; na sessão atual seguir é opcional. No fluxo legado, zero pula a etapa de seguir e
apresenta duas etapas; um ou dois ajustam o mínimo; três ou mais pedem três.
Elegibilidade exige outra conta com perfil ativo e onboarding concluído. A API
retorna até 20 sugestões e prioriza seleções já persistidas para que continuem
visíveis. Antes de avançar da seleção de obras ou concluir o cadastro, o app
atualiza a disponibilidade. A etapa de pessoas também permite puxar para atualizar.
Contas retiradas deixam de ser exigidas; se novas sugestões aumentarem o mínimo,
o app mantém as demais escolhas e informa o que mudou. Falha de rede não equivale
a comunidade vazia e não libera uma conclusão sem confirmação da API.

Um universo sem obras permite continuar com uma mensagem informativa. Na Home,
a seção de descoberta usa obras publicadas do catálogo, inclusive IDs novos;
contagens são totais reais, sem alegar tendência semanal ou atividade de amigos.
A ausência de notas e de reviews convida ao primeiro registro. Os cards de universo mostram quantidade de itens; presença real fica nas salas.

Sugestões de pessoas de exemplo ficam restritas ao modo de demonstração.
A sessão real usa a [API de pessoas](people.md): busca por nome/@usuário, perfis
e seguir/deixar de seguir persistidos. A Home só apresenta a seção quando há
loristas elegíveis ainda não seguidos; uma falha de consulta tem retry, sem ser
tratada como comunidade vazia. Outros módulos do
protótipo permanecem fora desta etapa; estas regras não tornam o app inteiro
pronto para lançamento. Todos os novos textos têm PT-BR e inglês.

## Verificação

Testes HTTP com PostgreSQL isolado cobrem seed, PT/EN, fallback, publicação, novos
IDs e rejeição transacional sem modificar progresso salvo. Os testes iOS cobrem
decodificação, idioma, falha/retry sem fallback fictício, integridade referencial e
um catálogo com apenas um universo. O lote de paginação também cobre 125 edições,
limites/cursor/fallback, resolve publicado, cache, cancelamento e restauração de escolhas.
Publicar a API antes da versão do app que consome as novas rotas; este lote não cria migration. O predeploy do Railway executa `npm run db:migrate`.

## Carga reduzida e navegação — contrato do lote 28/10/2026

- `GET /catalog` conserva o snapshot legado. O novo cliente usa
  `GET /catalog/bootstrap`: mesmos universos/totais, seleção inicial limitada por
  universo para descoberta, onboarding e oito mais bem avaliados. Metadados
  incluem `discoveryIDs`, `onboardingIDs`, `topRatedIDs` e média agregada.
- `GET /catalog/items` pagina até 50 itens (30 por padrão), com `q`, `category`
  (`all`, `works`, `characters`, `events`, `consumable`), `universe`, `series` e
  `after`. Busca combina palavras sem acentos/caixa em título e universo. Cursor
  opaco vinculado ao idioma/filtros; séries ordenam posição numérica + ID.
- `GET /catalog/series` pagina até 30 descritores (20 por padrão); `universe` filtra.
  Cada descritor contém id/título/ano/universo e total publicado, independente da
  página de edições. `GET /catalog/series/:id` resolve a abertura por link direto.
- `GET /catalog/resolve?ids=...` resolve até 50 IDs exatos publicados. Retorna
  `items` e `missingIDs`; ausência confirmada é diferente de falha de rede.
- Referências compactas de obras vistas/registradas são agregadas ao resumo privado
  da atividade para preservar progresso mesmo sem carregar seus metadados completos.
  Biblioteca, listas, ordens e favoritos resolvem apenas suas próprias referências.
- Todas as leituras usam PostgreSQL existente, publicação ativa e fallback PT/EN.
  Não há consulta a provedores externos nem contratação de serviço. Clientes antigos
  continuam compatíveis. Retirada editorial é refletida ao atualizar as consultas.
