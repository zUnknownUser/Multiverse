# Fontes externas: Marvel, primeira etapa

O app continua lendo `GET /api/v1/catalog`; fornecedores nunca são chamados pelo
mobile. `providers/wikidata.ts` cuida do transporte/normalização, `marvel-registry.ts`
identifica explicitamente obras e personagens, e `import-marvel.ts` publica em uma
transação. Controller e serviço de leitura permanecem separados. Não há chave
externa nova nesta etapa. Chaves de provedores futuros pertencem ao ambiente/secrets
do backend, nunca ao app, ao registro editorial ou ao Git.

## Fonte e limites

Integração real com [Wikidata](https://www.wikidata.org/wiki/Wikidata:Data_access),
cujos dados estruturados são [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing).
Não é a API oficial da Marvel. A disponibilidade do antigo portal da Marvel não
foi confirmada nesta implementação. Não fazemos scraping de páginas, cópia de
HQs, download de capas ou inferência de cronologia/cânone. Imagens e sinopses
completas exigem fonte e autorização próprias; a licença dos metadados não abrange
as imagens eventualmente referenciadas por uma entidade.

A seleção inicial é pequena e revisada: Fênix Negra e Guerras Secretas (2015)
reutilizam os IDs existentes; Dinastia M, The Infinity Gauntlet e Homem-Aranha
recebem IDs estáveis. Cada mapeamento confere também o título inglês esperado;
entidade renomeada/mesclada exige revisão, evitando trocar filme por HQ homônima.
HQ neste lote representa obra/arco, não cada edição individual. Filmes e séries
são aceitos pelo contrato de consulta, mas ainda não têm fonte externa vinculada.
Para eles, avaliar TMDB e sua licença comercial/atribuição antes da integração:
https://developer.themoviedb.org/docs/faq

## Sincronização operacional

Na pasta `backend/api`, com dependências instaladas:

```sh
npm run build
node scripts/sync-marvel.mjs             # prévia, sem escrever no banco
npm run db:migrate                     # inclui 006_catalog_sources.sql
node scripts/sync-marvel.mjs --write    # banco definido por DATABASE_URL
```

Rodar de novo é seguro. Busca sequencial, timeout de 15 segundos por entidade,
limite de resposta e interrupção em 429/erro evitam tempestades de tentativas.
Todos os dados são obtidos e validados antes da transação. Falha não apaga o último
catálogo publicado. O lock impede importações simultâneas conflitantes; revisão
antiga não substitui uma mais nova. Não existe rota pública de importação, tarefa
em cada login, sincronização no boot nem cron automático nesta etapa.

`catalog_sources` guarda fornecedor, ID, URL, revisão, data da consulta e metadados
PT/EN normalizados. Só novos registros ganham texto inicial da fonte; sincronizações
atualizam os metadados de origem e preservam o texto editorial publicado, status,
IDs, reviews e diários. Cópia revisada existente não é sobrescrita automaticamente.
Português prefere `pt-br`, depois `pt`; título original é fallback. Descrição sem
tradução apresenta uma mensagem localizada de indisponibilidade. Cânone desconhecido
aparece como “—”; ano desconhecido não é inventado. IDs de criadores/editoras são
referências Wikidata; seus nomes e relações ainda não são exibidos no app.

## Consultas da nossa API

- `GET /api/v1/catalog/marvel?type=HQ&q=guerra&limit=20&after=m-civil`:
  `{ locale, total, items, nextCursor }`. Filtros opcionais, limite 1–50, cursor é
  o ID do último item. Reutilizar os mesmos filtros ao continuar a lista. Tipos:
  `HQ`, `Personagem`, `Evento`, `Filme`, `Série`. Consulta sem resultados retorna
  200 com lista vazia. A paginação usa o snapshot atual e ordena por ID; pode haver
  novos itens entre consultas. Para catálogo grande, migrar o snapshot/filtro
  compartilhado para paginação SQL; a primeira carga do iOS ainda é integral.
- `GET /api/v1/catalog/marvel/:id`: `{ locale, item, sources }`, 404 para item
  desconhecido, arquivado ou de outro universo. Metadados de origem ficam separados
  da apresentação editorial e não são enviados como notas/avaliações.
- `Accept-Language` seleciona PT-BR/EN. Parâmetros inválidos retornam 400
  `INVALID_CATALOG_QUERY`; banco indisponível retorna 503, nunca catálogo fictício.

## O que aparece no iOS

Após nova abertura do app, os novos itens entram na busca, catálogo Marvel e seletor
para registrar no diário, usando os mesmos cards/tipografia. Duas HQs novas e um
personagem se somam aos itens editoriais. A tela não ganha dados técnicos de origem.
As fontes completas ficam disponíveis na API para uma futura apresentação de
créditos. Capas mantêm a representação visual atual. Não há descoberta automática
de todo o universo Marvel, timeline externa ou atualização de feed social.
