# Marvel catálogo publicado e fontes externas

## Entrega e limites

O iOS lê nosso PostgreSQL por `GET /api/v1/catalog`. Fornecedores externos não
participam do login, da busca ou da abertura de uma obra. Uma indisponibilidade
externa preserva o último catálogo publicado. As notas, reviews, diários e cânone
editorial do Multiverse não são substituídos por dados de fornecedores.

| Fonte    | Escopo implementado                                                                                 | Estado                                                                                                |
| -------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Wikidata | Identidade, títulos PT/EN, descrições curtas, ano e referências de criadores/editoras               | Integração publicada, cinco mapeamentos revisados                                                     |
| Metron   | Edições de HQ: série, número, datas, páginas, créditos e personagens                                | 30 edições revisadas de quatro séries completas, com PT-BR editorial e EN da fonte                    |
| TMDB     | Filmes/séries: títulos e sinopses PT/EN, estreia, duração de filme, créditos e referência de pôster | Credencial configurada e respostas reais validadas para três obras; publicação operacional disponível |

Não há scraping, descoberta irrestrita, mensagens diárias, importação de avaliações
externas ou novas telas. Capas continuam com o visual existente. Dados revisados do TMDB e da Metron ficam disponíveis também na API de detalhe; campos sem apresentação no app não criam novas telas. Não se promete retenção
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
- `metron-registry.ts` / `publish-metron.ts`: lote revisado de 30 edições,
  identificado por ID da edição e da série, nome, ano e número. Cria obras próprias,
  sem substituir sagas. Títulos/sinopses PT-BR adaptados editorialmente; EN vem da
  fonte. Preserva textos editoriais e arquivamento em novas sincronizações.
- `publish-tmdb.ts`: publica somente o lote completo dos três mapeamentos TMDB revisados em `catalog_sources`, após validação e autorização de uso. Sincronização antiga não substitui uma mais recente; não altera texto editorial, status, IDs ou atividade.
- `catalog-description.ts`: sinopse TMDB/Metron publicada no idioma pedido, com fallback editorial. Catálogo, detalhe e referências do diário usam a mesma regra.
- `CatalogService`/`MarvelService`: consultas somente ao catálogo publicado.

## Credenciais e uso dos conectores preparados

Segredos somente no `.env` ignorado ou nas variáveis privadas do Railway:

- `TMDB_READ_ACCESS_TOKEN`: **API Read Access Token**, obtido em
  [TMDB > Settings > API](https://www.themoviedb.org/settings/api).
- `METRON_API_TOKEN`: token da conta [Metron](https://metron.cloud/), enviado como
  Bearer. [Gerar token](https://metron.cloud/accounts/tokens/). [Documentação](https://metron.cloud/docs/).

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
# Publica as 30 edições revisadas das quatro séries:
node scripts/preview-marvel-sources.mjs --provider=metron --publish
```

Prévia/revisão Metron aceita até dez IDs distintos por lote, separados por vírgula.
A publicação busca as 30 edições do registro em grupos de até dez, com 3,1 segundos
entre requests, inclusive na troca de grupo. Todos os dados são obtidos antes da
transação; a publicação é atômica. O comando leva cerca de dois minutos. Não repita comandos em paralelo nem tente contornar 429. O lote para no primeiro erro, sem gravar resultado parcial. HTTP 401/403 indica
credencial/permissão; 429 indica cota; `UNAVAILABLE` indica rede/timeout; divergência
de obra é um erro de mapeamento. Não é erro da conta do usuário do app.

Consulta administrativa dos candidatos, pelo banco privado:

```sql
SELECT provider, external_id, suggested_item_id, kind, metadata, attribution, fetched_at
FROM catalog_import_candidates ORDER BY provider, external_id;
```

Não existe cron ou publicação durante o login. `--publish` grava o lote revisado completo do provedor em uma transação. IDs Metron arbitrários continuam restritos à prévia/revisão; publicação exige exatamente o lote registrado. A migração `007` cria a revisão privada; `008` permite TMDB e `014` permite Metron em `catalog_sources`. `015` cria séries, traduções e vínculos de edições com posição numérica única. Para reverter uma publicação, remover somente sua linha de `catalog_sources` faz a sinopse voltar ao texto editorial preservado.

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
  sobre imagens. Em 02/10/2026, a credencial foi validada com respostas reais.
  O publisher real é `{id:1,name:"Marvel"}`; o conector aceita essa identidade e
  o alias antigo "Marvel Comics", exigindo ID 1. O nome real de uma série é
  "The Infinity Gauntlet". Créditos gerais e por obra indicam a fonte, CC BY-SA 4.0
  e a adaptação editorial do texto português. Não são importadas imagens/páginas.
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
  continuam privados; dados TMDB/Metron publicados por `--publish` entram em `sources` com atribuição e data da consulta.
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

## Metron: séries e idiomas

| Série PT-BR / EN                         | Edições | Série Metron | IDs das edições |
| ---------------------------------------- | ------- | ------------ | --------------- |
| Guerra Civil / Civil War                 | #1–7    | 402 (2006)   | 3726–3732       |
| Dinastia M / House of M                  | #1–8    | 1761 (2005)  | 21884–21891     |
| Guerras Secretas / Secret Wars           | #1–9    | 2019 (2015)  | 27065–27073     |
| Desafio Infinito / The Infinity Gauntlet | #1–6    | 3047 (1991)  | 42511–42516     |

IDs Multiverse: `m-metron-issue-<ID>`. São as edições originais em inglês, com ficha
localizada; não correspondem a uma edição impressa brasileira. Sinopses PT-BR são
adaptações editoriais revisadas, salvas na tabela de traduções. O conector mantém
PT ausente no metadata da fonte, sem atribuir à Metron uma tradução que ela não
forneceu. EN usa a sinopse publicada com fallback editorial se ausente. Atualizar
PT exige revisão editorial; não há tradução automática nem cópia de EN para PT.

Título, idioma, sinopse e estatísticas são consistentes no catálogo, busca, detalhe,
diário e referências do feed. Notas/contagens vêm somente da atividade Multiverse.
Metron fornece metadados, não páginas para ler a HQ, assinatura ou leitor digital.
O lote não representa o catálogo completo da Marvel e não adiciona pôsteres/capas.

Validação desta expansão: 75 testes unitários + 88 HTTP/PostgreSQL, 170 testes iOS,
938 entradas PT/EN. Respostas autenticadas das 30 edições conferidas. Testes HTTP
cobrem idiomas, séries, diário, favoritos, desejos/listas e reimportação sem perda
ou duplicação de dados pessoais. Testes iOS cobrem ordem numérica, releituras e
recuperação após falha. Não equivalem a homologação manual em aparelho. Token somente em `.env` ignorado e variáveis privadas do Railway.
Para rotacionar, substituir `METRON_API_TOKEN` nesses dois locais; não alterar app,
IDs ou dados publicados. Não há token no app nem no histórico Git.

### Navegação por série

Cada obra vinculada recebe `series: {id,title,year,number,position}` no catálogo,
no diário e nas referências do feed. Obras sem série retornam `null`. Os títulos
são localizados por `Accept-Language`; posição numérica é independente de idioma.
As tabelas editoriais não são sobrescritas por uma sincronização posterior.
Os quatro IDs #1 e as sagas existentes são preservados durante a expansão.

O iOS organiza as edições em Busca → Séries de HQs, Universo → Séries de HQs e
no botão “Ver edições da série” da obra. A ordem segue `position`, nunca comparação
alfabética do título. Progresso conta obras distintas registradas no diário;
releituras não somam outra edição. Favoritar ou salvar um desejo não marca como lido.
Listagem/progresso usam as obras publicadas carregadas, sem inventar edições ausentes.
