# Duelo do Dia: fila renovável e sugestões

A migração 027 remove a dependência do rodízio de 14 perguntas. Há uma reserva inicial de **40 discussões inéditas**, 20 Marvel e 20 DC, em PT-BR/EN, alternando histórias, personagens, mundos, adaptações e debates. Ela é conteúdo real editorial, consumido uma vez. A fila pode receber novas perguntas sem atualizar o app ou fazer deploy.

## Publicação e preservação

- Uma rodada global por data UTC. O primeiro acesso autenticado do dia materializa a rodada em uma transação; não há cron nem polling novo. Primeiro vem o agendamento da data, depois agendamentos atrasados, sugestões da comunidade aprovadas sem data e reserva editorial sem data. Datas futuras nunca são antecipadas.
- Se ninguém abrir em uma data, não criamos votos/rodadas retroativos. Seu agendamento permanece elegível depois da data e cede prioridade ao agendamento do dia atual.
- Rodadas publicadas, traduções, prazo, votos, pontos, ranking e convites permanecem preservados. A mudança não substitui a rodada já existente de hoje. Cada pergunta selecionada cria um post editorial novo, com zero votos; o post original e seus votos são independentes.
- Identidades normalizadas de título + opções (ordem das opções ignorada) são guardadas para os dois idiomas. A migração inclui as perguntas já publicadas. Duplicatas exatas normalizadas são rejeitadas; equivalência semântica ainda depende da revisão humana.
- Não há repetição automática ao esgotar a reserva: `today=null`, histórico anterior preservado e mensagem de preparação com acesso a sugestões no app. É preciso abastecer a fila; não é geração infinita/IA automática.
- O número de pontos continua 10 por voto válido na rodada, uma vez. Sugerir uma pergunta não dá pontos adicionais. Os marcos de perfil existentes continuam usando participações reais.

## Fluxo do usuário

1. Home → **Sugira o próximo duelo** → criar um duelo na comunidade.
2. Na própria publicação: **Sugerir para o Duelo do Dia** e confirmar a revisão/adaptação em PT-BR/EN e o crédito público.
3. **Minhas sugestões** mostra revisão, fila/agendamento, publicação, retirada ou não seleção (até 100 recentes).
4. Pode retirar antes da publicação. Retirada/rejeição é terminal para aquele post; uma nova ideia requer novo post. Repetir um envio não duplica nem reabre a candidatura.

São aceitos apenas duelos do próprio autor, disponíveis, fora de clubes, sem spoilers e sem segmento restrito. Até três sugestões pendentes/aprovadas e três novas em 24 horas, por conta. A operação é serializada para impedir bypass concorrente. Alteração, exclusão ou moderação do post antes da publicação invalida sua candidatura: a revisão não autoriza mudanças posteriores silenciosas. O texto aprovado é uma adaptação editorial congelada, não uma cópia dinâmica do post.

A arena mostra **Ideia de @usuário**, com acesso ao perfil. Bloqueio oculta o crédito para o observador; exclusão da conta apaga candidatura/snapshot/decisões associados e remove o crédito, conservando a rodada editorial já publicada e seu histórico agregado. Candidaturas só são consultáveis pelo autor. Não há endpoint de aprovação acessível a usuários.

## Operação editorial privada

Segue o padrão de `scripts/moderate.mjs`: ferramenta administrativa com conexão privada ao PostgreSQL, nunca com credenciais no app. Requer Node compatível com o projeto e `npm run build` em `backend/api`. Obtenha `CURATION_DATABASE_URL` pelo mecanismo de segredos do ambiente; não grave em arquivos versionados.

```sh
node scripts/curate-duels.mjs --queue
node scripts/curate-duels.mjs --file decision.json
node scripts/curate-duels.mjs --file decision.json --execute
```

Sem `--execute`, só valida o formato localmente e não abre conexão. Conflitos com banco/datas/histórico só são verificados no apply. A fila retorna contadores por status e até 200 candidatos ativos. Revise regularmente e mantenha reserva de pelo menos 30 dias; não há alarme automático de estoque nesta entrega.

Exemplo de `decision.json` para aprovar uma candidatura existente:

```json
{
  "id": "fc8510b7-7ec9-4f7b-8641-b27ffb4f2d7f",
  "candidateID": "6c2f384c-8ed7-4415-8eab-41d31686f844",
  "action": "approve",
  "operator": "editor",
  "reason": "Revisão editorial e dos dois idiomas concluída",
  "universe": "dc",
  "category": "stories",
  "scheduledOn": null,
  "translations": {
    "pt-BR": {
      "title": "Qual tipo de história do Batman você quer ler agora?",
      "text": "Escolha um lado e conte o que te atrai nessa proposta.",
      "optionA": "Mistério de bairro",
      "optionB": "Aventura com a Batfamília"
    },
    "en": {
      "title": "What kind of Batman story would you like to read now?",
      "text": "Pick a side and tell us what draws you to that premise.",
      "optionA": "Neighborhood mystery",
      "optionB": "Bat-family adventure"
    }
  }
}
```

Substitua os UUIDs: `id` identifica a decisão, `candidateID` vem da fila. Reutilize **o mesmo arquivo/id** num retry; uma decisão reaplicada é idempotente, e reutilizar o ID com outro conteúdo falha. `scheduledOn` é `YYYY-MM-DD` UTC ou null para reserva. Datas passadas, ocupadas ou com rodada já publicada não são aceitas.

- `action=create`: novo `candidateID` UUIDv4; cria e aprova uma pergunta editorial com traduções completas. Permite abastecer a reserva sem novo deploy.
- `action=approve`: aprova pendente ou altera tradução/data de uma aprovada, sempre com nova decisão/id para alterações. Não muda perguntas publicadas. Autor/universo da sugestão não podem ser trocados.
- `action=reject`: `id`, `candidateID`, `operator`, `reason`; rejeita uma pendente/aprovada. Razão administrativa é privada; app recebe apenas um código seguro, traduzido.
- Categorias: `debate`, `stories`, `characters`, `worlds`, `adaptations`. Ambos os idiomas obrigatórios: título até 140, texto até 2000, opções distintas até 120 caracteres.

Revisão humana deve garantir clareza, ausência de spoilers, equivalência das traduções, diversidade de assuntos/universos e preservar a ideia do autor. A ferramenta não faz tradução, pesquisa factual nem curadoria automática. Não há painel administrativo visual nem notificação push de aprovação nesta entrega.

## Rotas de usuário

- `GET community/duel-candidates/mine`
- `GET community/duel-candidates/posts/:id`
- `PUT community/duel-candidates/posts/:id` (idempotente)
- `DELETE community/duel-candidates/posts/:id` (retirada idempotente antes da publicação)

Todas autenticadas, exigem onboarding e retornam `Cache-Control: no-store`. O contrato anterior de `community/daily-duels` ganha apenas `contributor` opcional; clientes antigos continuam funcionando.
