# Capas do catálogo

Implementação de 03/10/2026. Preserva as dimensões, molduras, sombras, tipografia,
cores e navegação existentes. A imagem substitui somente a arte interna da capa.

## Fonte e identidade

- `Item.cover`: objeto opcional `{provider,url,sourceURL}`. Ausência ou URL inválida
  mantém o fallback; itens antigos continuam decodificando sem o campo.
- Snapshot, catálogo paginado/detalhe, diário e feed entregam a mesma projeção.
- Fonte já vinculada em `catalog_sources`: TMDB para filmes/séries, Metron para
  edições individuais. Não há busca por título durante navegação nem chave no app.
- Importador Metron agora preserva `image` como `metadata.posterURL`, após validar
  HTTPS, host e caminho. TMDB já capturava `posterURL`.
- Migration 022 atualiza apenas URLs dos 33 vínculos existentes e conferidos:
  30 edições Metron (Guerra Civil, Dinastia M, Guerras Secretas 2015, Desafio Infinito)
  e três TMDB (Ultimato, Através do Aranhaverso, Loki). Dados obtidos em 03/10/2026.
  Não cria obras, não muda títulos/sinopses/progresso e não chama APIs no deploy.
- A expansão 023 acrescenta DC e mais Marvel: 119 novas obras e três vínculos
  com obras existentes. Personagens e obras sem fonte confirmada conservam o fallback. Uma capa de #1 não passa a representar o arco ou encadernado inteiro.
- Texto da interface e do catálogo permanece PT-BR/EN. A capa é a arte da edição
  original: texto impresso nela não é traduzido nem representa uma edição brasileira.

## iOS e performance

`CatalogCoverOverlay` não participa do layout nem intercepta toques. Todos os
`PosterView` recebem a imagem, além das miniaturas de feed/conversa e componentes
legados de personagem/conexões (somente quando houver dado real apropriado).

`CatalogCoverLoader` compartilha tarefas entre consumidores da mesma URL/tamanho.
Ao sair da tela libera a assinatura; cancela download quando não há consumidores.
Cache HTTP dedicado: 8 MB em RAM/64 MB em disco; imagens decodificadas: até 32 MB
ou 120 entradas. Sem cookies/credenciais, até quatro conexões por host, timeout
15s por request/25s total. CDN TMDB usa w185/w342/w500; Metron usa URL fornecida.
Decodificação/downsampling fora da main actor, no máximo 1024 pixels e 8 MB por
resposta, checando status/MIME e rejeitando redirecionamentos. Imagens não recebem
filtros, halftone sobreposto, animações novas ou alterações de cor. O recorte segue
as proporções anteriores. Falha/offline mantém a composição gráfica já existente.

## Atualização operacional

Após build, os comandos existentes atualizam dados/capas a partir das fontes:

```sh
node scripts/preview-marvel-sources.mjs --provider=tmdb --publish
node scripts/preview-marvel-sources.mjs --provider=metron --publish
```

Executar em ambiente privado com DATABASE_URL e tokens apropriados. Não colocar
credenciais em argumentos ou Git. Metron mantém ritmo abaixo de 20 consultas/minuto.
Novos vínculos exigem conferência da identidade; não ampliar a lista por nome solto.

## Créditos e uso

Ajustes mantém logo/aviso oficial TMDB, crédito Metron e CC BY-SA dos metadados.
Novo texto PT-BR/EN distingue a licença dos metadados da titularidade das ilustrações.
Esta implementação não concede licença comercial nem afirma que capas sejam CC BY-SA.
TMDB exige tratar o uso comercial com o provedor; condições de imagens Metron e
respectivos titulares continuam assunto a confirmar antes de distribuição comercial.

Fontes: [TMDB imagens](https://developer.themoviedb.org/docs/image-basics),
[TMDB FAQ e atribuição](https://developer.themoviedb.org/docs/faq),
[Metron API](https://github.com/Metron-Project/metron/blob/master/api/README.md),
[Metron boas práticas](https://metron-project.github.io/blog/api-best-practices).

## Verificação

- Testes API: normalização/URLs inválidas, vínculo correto, fallback, PT-BR/EN,
  snapshot/detalhe e migration sobre fontes já publicadas, preservando metadados.
- Testes iOS: compatibilidade, escolha de tamanho, cache/coalescência, downsampling,
  respostas inválidas e cancelamento. Conjunto completo: 217 testes.
- API: 93 unitários e 131 HTTP/PostgreSQL; lint, tipos, build e formatação.
- 1111 entradas PT-BR/EN validadas. Render de QA com PosterView real e duas imagens
  reais conferido no simulador, lado a lado com fallback, em tamanhos 96×144 e 118×177.

## Expansão de conteúdo — 03/10/2026

Migration 023 publica um lote conferido de 122 fontes: 119 novas obras, o vínculo
TMDB de O Cavaleiro das Trevas e capas de edições completas para Watchmen/Crise.
São 62 revistas DC em sete séries completas e 57 novos filmes/séries Marvel/DC.
As sete séries são Crise nas Infinitas Terras (12), Watchmen (12), Reino do Amanhã (4),
Flashpoint (5), O Longo Dia das Bruxas (13), O Cavaleiro das Trevas (4) e Grandes
Astros: Superman (12). Cada edição tem ID próprio e progresso independente.

Watchmen usa a edição DC Compact Comics que reúne #1–12; Crise usa a edição
Absolute que reúne #1–12. Essas fontes são `artworkOnly`: não mudam o ano original,
a sinopse editorial ou o progresso da obra agregada. Reino do Amanhã e Flashpoint
agregados permanecem sem capa confirmada; as revistas individuais têm capas reais.
A identidade foi conferida por IDs, série, ano, número e editora, nunca só pelo título.

TMDB fornece sinopses/títulos PT-BR/EN; as sinopses DC em português são adaptações
curtas revisadas das fontes. Metadados de fonte incluem créditos, personagens,
datas, páginas/duração, editora, formato/ISBN quando disponíveis e, para audiovisual,
elenco/gêneros e quantidade de temporadas/episódios quando informados. Estes detalhes
estão no endpoint de fonte; não foram criados novos painéis na interface.

As rotas paginadas e de detalhe agora aceitam `/catalog/dc` e `/catalog/marvel`;
outros escopos retornam 404. Snapshot permanece leve, com metadados extensos somente
no detalhe. Todas as capas do lote responderam HTTP 200. Nenhum engajamento da fonte
foi importado: notas, votos, reviews e progresso continuam derivados dos usuários.

Atualizar o lote aprovado sem duplicar obras:

```sh
node scripts/sync-heroes.mjs           # busca e valida, sem publicar
node scripts/sync-heroes.mjs --publish # transação no banco configurado
```

Falha de fonte/tradução/identidade interrompe o lote. Consultas Metron espaçadas
em 3,3 segundos; nada roda durante login, navegação ou inicialização da API.
Novas seleções exigem revisão explícita do registro. Arquivamento e traduções
editoriais existentes são preservados. A migration é uma fotografia dos dados
normalizados obtidos em 03/10/2026; não exige API externa durante deploy.

Validação desta expansão: 98 testes unitários API e 132 HTTP/PostgreSQL, incluindo
migration reaplicada, séries completas, preservação de agregados e rotas DC.
