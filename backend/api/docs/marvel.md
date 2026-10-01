# Marvel catálogo publicado e fontes externas

## Entrega e limites

O iOS lê nosso PostgreSQL por `GET /api/v1/catalog`. Fornecedores externos não
participam do login, da busca ou da abertura de uma obra. Uma indisponibilidade
externa preserva o último catálogo publicado. As notas, reviews, diários e cânone
editorial do Multiverse não são substituídos por dados de fornecedores.

| Fonte    | Escopo implementado                                                                                 | Estado                                                                                                |
| -------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Wikidata | Identidade, títulos PT/EN, descrições curtas, ano e referências de criadores/editoras               | Integração publicada, cinco mapeamentos revisados                                                     |
| Metron   | Edições de HQ: série, número, datas, páginas, créditos e personagens                                | Conector e revisão privada preparados; falta token e validação com respostas reais                    |
| TMDB     | Filmes/séries: títulos e sinopses PT/EN, estreia, duração de filme, créditos e referência de pôster | Credencial configurada e respostas reais validadas para três obras; publicação operacional disponível |

Não há scraping, descoberta irrestrita, mensagens diárias, importação de avaliações
externas ou novas telas. Capas continuam com o visual existente. Dados revisados do TMDB ficam disponíveis também na API de detalhe; campos sem apresentação no app não criam novas telas. Não se promete retenção
medida: esta etapa remove obstáculos concretos à descoberta e ao registro, mantendo
IDs estáveis e os dados pessoais intactos.

## Responsabilidades

- `provider-http.ts`: HTTPS com hosts e caminhos fixos para provedores com token,
  credencial no header, timeout de 15 segundos, sem redirecionamento/retry automático,
  leitura limitada a 2 MB de bytes descomprimidos, cancelamento e erros sem segredos.
  O leitor limitado também é usado pelo Wikidata.
- `wikidata.ts`, `metron.ts`, `tmdb.ts`: normalização específica e seleção explícita
  dos campos úteis. Payload bruto não é persistido. Sem tradução inventada nem
  sinopse inglesa marcada como portuguesa.
- `marvel-registry.ts`: IDs editoriais Wikidata revisados; `tmdbMarvelRegistry`
  relaciona Ultimato, Através do Aranhaverso e Loki aos IDs existentes, conferindo
  também título, tipo e ano.
- `metronMarvelSeries`: primeira seleção de séries/anos: Civil War (2006), House of M
  (2005), Secret Wars (2015), Infinity Gauntlet (1991). Editora Marvel por si só não
  basta, pois ela também publica universos licenciados. HQ individual recebe
  identidade própria; nunca substitui automaticamente o arco inteiro.
- `import-marvel.ts`: publicação Wikidata transacional e idempotente, sem substituir
  texto editorial, status ou IDs existentes; não regride revisão da fonte.
- `stage-candidates.ts`: grava apenas em `catalog_import_candidates`, separado do
  catálogo público. Lote inválido é revertido, identidade conflitante é recusada,
  consulta antiga não sobrescreve uma consulta mais recente.
- `publish-tmdb.ts`: publica somente o lote completo dos três mapeamentos TMDB revisados em `catalog_sources`, após validação e autorização de uso. Sincronização antiga não substitui uma mais recente; não altera texto editorial, status, IDs ou atividade.
- `catalog-description.ts`: sinopse TMDB publicada no idioma pedido, com fallback editorial. Catálogo, detalhe e referências do diário usam a mesma regra.
- `CatalogService`/`MarvelService`: consultas somente ao catálogo publicado.

## Credenciais e uso dos conectores preparados

Segredos somente no `.env` ignorado ou nas variáveis privadas do Railway:

- `TMDB_READ_ACCESS_TOKEN`: **API Read Access Token**, obtido em
  [TMDB > Settings > API](https://www.themoviedb.org/settings/api).
- `METRON_API_TOKEN`: token da conta [Metron](https://metron.cloud/), enviado como
  Bearer. [Documentação](https://metron.cloud/docs/).

Eles são opcionais e usados somente pelo comando operacional. Ausência de chave
não impede a API de iniciar; o comando retorna `TMDB_NOT_CONFIGURED` ou
`METRON_NOT_CONFIGURED`, sem fazer requests.

Na pasta `backend/api`:

```sh
npm run build
npm run db:migrate
# Prévia dos três filmes/séries já mapeados, sem escrever no banco:
node scripts/preview-marvel-sources.mjs --provider=tmdb
# Guarda os candidatos para revisão privada, sem publicar:
node scripts/preview-marvel-sources.mjs --provider=tmdb --stage
# Publicação explícita do lote TMDB revisado (licença e créditos necessários):
node scripts/preview-marvel-sources.mjs --provider=tmdb --publish
# Substitua ID por um ID numérico real da edição no Metron:
node scripts/preview-marvel-sources.mjs --provider=metron --issues=ID --stage
```

Metron aceita até dez IDs distintos por lote, separados por vírgula, e aguarda
3,1 segundos entre requests. Não repita comandos em paralelo nem tente contornar 429. O lote para no primeiro erro, sem gravar resultado parcial. HTTP 401/403 indica
credencial/permissão; 429 indica cota; `UNAVAILABLE` indica rede/timeout; divergência
de obra é um erro de mapeamento. Não é erro da conta do usuário do app.

Consulta administrativa dos candidatos, pelo banco privado:

```sql
SELECT provider, external_id, suggested_item_id, kind, metadata, attribution, fetched_at
FROM catalog_import_candidates ORDER BY provider, external_id;
```

Não existe cron ou publicação durante o login. `--publish` é exclusivo do TMDB e grava o lote completo em uma transação. Metron continua privado e pendente de credencial/validação. A migração `007` cria a revisão privada; `008` permite a origem TMDB no catálogo. Para reverter uma publicação, remover somente sua linha de `catalog_sources` faz a sinopse voltar ao texto editorial preservado.

## Fontes, manutenção e autorização de uso

- **Wikidata**: [acesso](https://www.wikidata.org/wiki/Wikidata:Data_access) e
  [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing) para dados estruturados.
  É adequado para identidade/referências, mas suas descrições são curtas e a
  cobertura/tradução variam. Não é a API oficial da Marvel.
- **Metron**: projeto comunitário com
  [código e contrato públicos mantidos](https://github.com/Metron-Project/metron).
  [Configuração oficial](https://github.com/Metron-Project/metron/blob/master/metron/settings.py)
  documenta Bearer, limites padrão e CC BY-SA 4.0 no schema da API. Atribuição e
  condições de redistribuição precisam ser atendidas; não se presume autorização
  sobre imagens. O site bloqueou a consulta automatizada sem login nesta revisão;
  o conector foi testado com fixtures baseadas no contrato, sem alegar homologação
  autenticada ou garantia de disponibilidade.
- **TMDB**: [contrato de filmes](https://developer.themoviedb.org/reference/movie-details),
  [séries](https://developer.themoviedb.org/reference/tv-series-details) e
  [agregação de subconsultas](https://developer.themoviedb.org/docs/append-to-response).
  Uma chamada por obra traz detalhes, traduções e créditos. A
  [FAQ oficial](https://developer.themoviedb.org/docs/faq) exige atribuição e logo
  em About/Credits; uso comercial requer licença comercial. Também não oferece SLA.
  O responsável informou em 01/10/2026 que já possui autorização comercial. O token de leitura foi validado em chamadas autenticadas, sem versionar seu valor. Ajustes → Créditos contém logo oficial e aviso de atribuição. O arquivo SVG foi obtido sem modificação da [página oficial de logos](https://www.themoviedb.org/about/logos-attribution).
- **Comic Vine** não foi incorporado: os
  [termos da API](https://comicvine.gamespot.com/api/) restringem uso comercial.
- O antigo portal de desenvolvedores Marvel não pôde ser validado; não é uma
  dependência do app. Não afirmamos que ele funciona ou que foi descontinuado com
  base apenas em relatos de terceiros.

## Wikidata: sincronização publicada

```sh
node scripts/sync-marvel.mjs            # prévia
node scripts/sync-marvel.mjs --write    # publicação no DATABASE_URL configurado
```

São cinco referências: Fênix Negra e Guerras Secretas (2015) reutilizam IDs;
Dinastia M, The Infinity Gauntlet e Homem-Aranha foram adicionados na etapa anterior.
Dados vêm antes da transação; lock protege a gravação. Só itens novos recebem texto
inicial da fonte. Português prefere `pt-br`, depois `pt`; o título original pode
ser fallback. Descrição ausente usa mensagem localizada. Cânone e ano não são
inferidos. `catalog_sources` conserva origem, revisão e data da consulta.

## API e desempenho

- `GET /api/v1/catalog/marvel?type=HQ&q=fenix&limit=20&after=m-civil` retorna
  `{ locale, total, items, nextCursor }`. Limite 1–50; cursor por ID em ordem estável.
  Busca ignora caixa e acentos, trata `%` e `_` literalmente e usa parâmetros SQL.
  Continuar com os mesmos filtros. Filtros e paginação são executados no PostgreSQL;
  cada request lê a contagem e a página no mesmo snapshot transacional. Publicações
  entre requests podem alterar o total. As estatísticas continuam calculadas pela
  view compartilhada; não há materialização de métricas nesta etapa.
- `GET /api/v1/catalog/marvel/:id` faz consulta restrita ao item Marvel publicado.
  Retorna `{ locale, item, sources }`; não carrega todos os universos/itens. Candidatos
  continuam privados; dados TMDB publicados por `--publish` entram em `sources` com atribuição e data da consulta.
- Tipos: `HQ`, `Personagem`, `Evento`, `Filme`, `Série`. `Accept-Language` escolhe
  PT-BR/EN. Busca vazia retorna 200 com lista vazia; entrada inválida, 400
  `INVALID_CATALOG_QUERY`; item indisponível, 404; banco indisponível, 503.
- iOS preserva a primeira carga integral do catálogo. A busca cria linhas em lotes
  de 40 e exibe mais conforme o scroll, usando `LazyVStack`. O limite invisível de
  14 foi removido. Busca `fenix` encontra `Fênix`, sem mudar títulos ou layout.
  Uma futura expansão massiva deve também paginar a carga inicial do mobile.

## O que o usuário já vê

O catálogo Marvel publicado, incluindo duas HQs novas e Homem-Aranha da etapa
anterior, continua acessível na busca e no registro do diário. Neste ajuste, o
usuário ganha acesso aos resultados antes escondidos e busca tolerante a acentos.
Ultimato, Através do Aranhaverso e Loki passam a usar sinopses TMDB em PT-BR/EN após a publicação operacional e recarga do catálogo. As credenciais ficam no backend. Notas e progresso continuam sendo do Multiverse. Não há capas TMDB/Metron,
cronologia externa, catálogo completo da Marvel ou feed social externo publicado.
