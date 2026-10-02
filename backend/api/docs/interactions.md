# Comentários, reações e revisão de denúncias

Etapa de 02/10/2026. Reutiliza os cards, a conversa e os ajustes existentes do iOS,
com PT-BR/EN. Depende da migration `011_review_interactions.sql` antes do servidor.

## Contratos autenticados

Todas as rotas usam `/api/v1`, token Firebase verificado e onboarding concluído.

| Rota                                            | Corpo / resultado                                                                |
| ----------------------------------------------- | -------------------------------------------------------------------------------- |
| `GET /reviews/:id/comments?after=…`             | `{reviewID,canComment,comments,users,nextCursor}`; 30 comentários por página     |
| `PUT /reviews/:id/comments/:commentID`          | `{text,spoiler}` → `{reviewID,commentID,saved}`                                  |
| `PUT /reviews/:id/reaction`                     | `{reaction,liked}` → resumo confirmado                                           |
| `PUT /reviews/:id/comments/:commentID/reaction` | Mesmo contrato, para um comentário                                               |
| `PUT /me/comment-permission`                    | `{commentPermission:"everyone"\|"following"\|"nobody"}` → privacidade confirmada |
| `PUT /reviews/:id/comments/:commentID/report`   | `{reason,alsoBlock}` → `{reported,reviewID,commentID,blockedUserID}`             |

O feed/detalhe incluem `interaction` e `commentCount` por review. O resumo contém
`id`, `likes`, `liked`, `myReaction` e contagens `reactions` de `POW!`, `ZAP!`,
`KRAK!`, `HEH`. Cada pessoa tem uma reação substituível/removível (`null`), além
de uma curtida independente. `reaction` deve estar presente, mesmo ao remover.
O backend não devolve a lista de pessoas que reagiram. Contagens excluem contas
em exclusão e relações bloqueadas, inclusive pelo autor da review/comentário.

## Regras e falhas

- Diário privado, review denunciada pelo leitor, moderação, catálogo arquivado e
  bloqueios recíprocos são reavaliados no servidor antes de ler ou interagir.
- “Quem sigo” significa **o autor segue quem comenta**, e não o contrário. É o
  padrão no servidor, sem importar automaticamente a antiga preferência local.
  “Ninguém” bloqueia comentários de terceiros; o autor pode responder à própria review.
  Mudar a permissão não apaga comentários existentes e não restringe reações.
- Comentários têm até 2.000 caracteres e sinalização de spoiler. A UI não expõe
  texto marcado antes de revelar e esconde a conversa quando a review está protegida.
- UUID v4 nasce no app. Repetir exatamente o envio confirma a mesma gravação;
  trocar autor, review ou texto com o mesmo UUID retorna `COMMENT_CONFLICT`.
  O app preserva o envio pendente e só limpa o rascunho após confirmação. Durante
  um envio incerto, tentar novamente usa o mesmo texto/UUID, sem edição concorrente.
- Paginação crescente por data de criação com microssegundos + UUID. Falha de
  atualização conserva a página conhecida; bloqueio/denúncia invalida respostas
  atrasadas. A leitura de um detalhe negado remove seu cache legível.
- Limites: 30 comentários novos por conta/hora, 120 alterações de reação por
  minuto de calendário e 50 denúncias novas por conta/24h, somando reviews e
  comentários. Repetições idênticas não consomem nova cota. Exclusão de conta
  remove comentários, reações e denúncias por cascata.
- Responder insere o @usuário, sem copiar texto de outro comentário. Não há árvore
  de respostas, menções com notificações, edição/exclusão individual ou rascunhos
  persistentes entre reinícios nesta etapa.

## Ferramenta administrativa

`scripts/moderate.mjs` é uma CLI operacional, **sem rota administrativa no app**.
Só funciona com uma conexão privada autorizada ao PostgreSQL em
`MODERATION_DATABASE_URL`. Não versionar nem imprimir a URL. Não recebe tokens
de usuários comuns como autorização administrativa. Use uma credencial de
operador separada com os privilégios mínimos necessários.

Depois de `npm run build`, consultar a fila:

```sh
node scripts/moderate.mjs --queue
```

A fila apresenta até 50 alvos pendentes, com texto, sinalização de spoiler, motivos
e quantidade de denúncias, em ordem da denúncia mais antiga. Não expõe identidade
dos denunciantes. Execute em terminal privado: contém conteúdo de usuários.

Depois da revisão humana, criar um UUID para a decisão e executar:

```sh
node scripts/moderate.mjs --execute --id UUID_DA_DECISAO \
  --type comment --target UUID_DO_COMENTARIO --action hide \
  --operator NOME_DO_OPERADOR --reason 'Motivo da decisão após revisão'
```

Tipos: `review` ou `comment`. Ações: `hide` oculta o conteúdo social, `dismiss`
encerra as denúncias mantendo a visibilidade atual, `restore` torna o conteúdo
visível novamente. Todas registram operador, papel PostgreSQL autenticado, motivo,
ação e data na mesma transação. Reutilizar o UUID confirma a decisão sem duplicar;
reutilizá-lo com outra decisão falha. Restaurar não desfaz o ocultamento pessoal
causado por uma denúncia. Ocultar review preserva o diário privado do autor.

IA, painel web, notificação ao autor, contestação e política editorial detalhada
permanecem pendentes. A ferramenta não toma decisões automaticamente nem promete
prazo de atendimento. Não foi aplicada nenhuma decisão a conteúdo de produção
durante o desenvolvimento desta etapa.

## Validação

Testes HTTP com PostgreSQL descartável cobrem permissões, idempotência, payloads,
bloqueios, privacidade, moderação, paginação, reações/curtidas, limites, exclusão,
auditoria e rollback. Testes iOS cobrem confirmação, falha/retry, respostas antigas,
isolamento entre contas e integridade dos contratos. Firebase é injetado nos testes.

Teste integrado com duas contas reais ainda precisa ser feito pelo titular:
autor publica review e permite “Todos”; leitor comenta/reage, reabre e confere;
autor muda para “Quem sigo”/“Ninguém”; leitor confere a restrição; testar denúncia,
bloqueio, perda de rede e reenvio, em português e inglês. A validação automatizada
não autentica contas reais nem envia denúncias para produção.
