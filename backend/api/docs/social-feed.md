# Feed de reviews, privacidade e proteção

Esta etapa conecta a Home às reviews reais da própria conta e de pessoas seguidas.
Mantém os componentes existentes e PT-BR/EN. Comentários e reações foram conectados na [etapa seguinte](interactions.md).
Posts livres, reposts, notificações e moderação por IA continuam pendentes.

## Visibilidade

`profiles.public_diary` começa em `false`, inclusive para contas existentes.
O ajuste antigo era local e não representa consentimento para publicar histórico.
Em Ajustes → Diário público, a pessoa pode liberar explicitamente suas reviews
anteriores e futuras para outras contas autenticadas. Desativar retira o conteúdo
das consultas sociais seguintes, preservando o diário privado. A tela de registro
informa a visibilidade conhecida, sem tratar falha de consulta como permissão.

O feed inclui a própria atividade mesmo com diário privado. Das outras pessoas,
inclui somente autores seguidos, ativos, com onboarding concluído e diário público.
Detalhes de uma review pública podem ser abertos por outra conta autenticada sem
seguir o autor. Ambas as consultas aplicam bloqueios recíprocos, denúncias do leitor,
moderação e disponibilidade da obra/universo. A API do diário continua exclusiva
da própria conta, incluindo seu histórico arquivado. Agregados de notas do catálogo
continuam seguindo as regras anteriores; não revelam texto privado.

## Contratos autenticados (`/api/v1`)

| Rota                         | Comportamento                                                       |
| ---------------------------- | ------------------------------------------------------------------- |
| `GET /feed?limit=20&after=…` | `{reviews,users,items,universes,nextCursor}`. Máximo 50 por página. |
| `GET /reviews/:id`           | Mesmo envelope com uma review, ou 404 `REVIEW_UNAVAILABLE`.         |
| `GET /me/privacy`            | `{publicDiary}` da conta autenticada.                               |
| `PUT /me/privacy`            | Define `{publicDiary:boolean}` e confirma o estado salvo.           |
| `GET /me/blocks`             | `{users:[{id,handle,createdAt}]}` bloqueados pela conta.            |
| `PUT /me/blocks/:id`         | Define `{blocked:boolean}`; resposta `{userID,blocked}`.            |
| `PUT /reviews/:id/report`    | `{reason,alsoBlock}`; confirma `{reported,reviewID,blockedUserID}`. |

O cursor preserva microssegundos e UUID, em ordem de criação decrescente. Não usa
offset nem data declarada no registro. Inserções novas não deslocam páginas antigas;
puxar para atualizar começa uma nova consulta. Alterações de visibilidade entre
páginas são reavaliadas. Metadados de catálogo seguem `Accept-Language`; texto do
autor não é traduzido. Índices por criação/autor e seleção limitada mantêm cada
página pequena, sem requisições individuais para cada card.

## Bloqueio e denúncias

Bloquear pelo menu ••• do perfil, ou junto com uma denúncia, impede que as contas
se encontrem na descoberta, abram perfis/reviews ou se sigam. `visible_follows`
filtra as relações em ambos os sentidos, incluindo contadores e onboarding.
As relações anteriores ficam suspensas: desbloquear volta a considerá-las, como
informado na tela de bloqueados. Uma denúncia continua ocultando aquela review
para o denunciante mesmo após desbloquear. As ações são idempotentes e vinculadas
ao UID do token, nunca a um @usuário mutável. A exclusão de conta limpa relações,
bloqueios e denúncias por cascata.

Motivos estáveis: `spoiler`, `offensive`, `spam`, `wrong_canon`, `other`. A primeira
denúncia por pessoa/review cria uma entrada em `review_reports`; repetir confirma
a mesma entrada. O bloqueio opcional e a denúncia usam a mesma transação. A UI
fecha apenas após confirmação, preservando seleção e erro em falhas. A API não
informa a identidade do denunciante ao autor e não promete prazo de atendimento.

Limites iniciais: 50 denúncias novas por conta em 24 horas e 20 reviews novas por
hora para contas com diário público. Repetir um salvamento com o mesmo UUID não
consome outra publicação. Respostas 429 explicam a espera e preservam o rascunho.
Esses limites são uma proteção inicial; não substituem moderação humana/antifraude.

A fila `review_reports.status='pending'` precisa de acompanhamento operacional.
Existe agora uma [CLI administrativa auditada](interactions.md); não há painel
nem análise automática. Operadores autorizados podem
revisar a fila pelo acesso administrativo já protegido ao banco. Uma decisão de
remoção usa `reviews.moderation_status='hidden'`; isso retira a review das rotas
sociais sem apagar o diário do autor. Marcar a denúncia como `reviewed` registra
seu processamento. Não há rota pública de administração. As decisões da CLI registram justificativa e operador. Painel,
notificação ao autor, contestação e triagem por IA continuam pendentes.

## App e validação

`SocialAPI`/`SocialStore` separam feed/proteções do catálogo, diário e descoberta.
Falha de atualização mantém a página já carregada; vazio bem-sucedido convida a
registrar/descobrir pessoas. Bloqueio, denúncia e mudança de relações invalidam
consultas antigas para que não recoloquem conteúdo removido. A abertura de uma
review revalida permissão antes de mostrar seu texto. Configurações e mutações
esperam confirmação; não usam sucesso de demonstração como fallback.

Migration necessária: `010_social_feed.sql`, executada antes do serviço pelo
predeploy do Railway. Testes HTTP com PostgreSQL isolado cobrem opt-in, revogação,
cursor com empate/microssegundos, bloqueios recíprocos, onboarding, idempotência,
rollback, arquivamento, limites e limpeza por exclusão. Testes iOS cobrem estados
vazios/erros, referências, paginação, confirmação, respostas atrasadas e isolamento.

Teste manual com duas contas: A ativa Diário público e registra uma review; B
segue A e atualiza a Home. A desativa o ajuste; B atualiza e não vê a review.
Reativar permite testar denúncia/bloqueio por B. Reabrir o app confirma persistência;
em Ajustes → Bloqueados é possível desbloquear. Repetir sem rede deve apresentar
erro sem confirmar a ação, e repetir em inglês deve manter os mesmos resultados.
