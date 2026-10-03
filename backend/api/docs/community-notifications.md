# Comunidade, atividade e preparação de push

Implementado em 02/10/2026. Migration aditiva `012_community_notifications.sql`.
Posts são públicos para membros autenticados, independentemente do opt-in do diário.
Não são reviews nem criam registros no diário. Universo obrigatório, obra opcional
validada contra o mesmo universo publicado. A interface permite publicar pela Home,
pelo universo ou pela obra; a obra é vinculada quando a composição parte dela.

## Contrato

Todas as rotas usam `/api/v1` e Firebase ID token, com onboarding concluído.

| Método/rota                                          | Comportamento                                                                                     |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| GET `/posts?universe=marvel&item=m-civilwar&after=…` | Descoberta global ou filtrada; 30 por página, cursor estável                                      |
| GET `/posts/:id`                                     | Post visível e autor                                                                              |
| PUT `/posts/:id`                                     | UUID v4 do cliente, `{universeID,itemID,title,text,spoiler}`; `itemID` deve existir ou ser `null` |
| DELETE `/posts/:id`                                  | Exclusão lógica apenas pelo autor; retries não revivem o post                                     |
| GET `/posts/:id/comments?after=…`                    | Comentários visíveis, autores, permissão e cursor                                                 |
| PUT `/posts/:id/comments/:commentID`                 | Texto e spoiler; mesma identidade em retries                                                      |
| PUT `/posts/:id/reaction`                            | `{reaction: null ou POW!/ZAP!/KRAK!/HEH, liked: boolean}`                                         |
| PUT `/posts/:id/comments/:commentID/reaction`        | Mesma regra, reação ao comentário                                                                 |
| PUT `/posts/:id/report`                              | Motivo válido e `alsoBlock`                                                                       |
| PUT `/posts/:id/comments/:commentID/report`          | Denúncia do comentário e bloqueio opcional                                                        |
| GET `/me/notifications?after=…`                      | Atividade, autores, cursor e contagem exata de não lidas visíveis                                 |
| PUT `/me/notifications/read`                         | `{ids:[UUID,…]}`, até 100; altera apenas notificações da própria conta                            |
| GET/PUT `/me/notification-preferences`               | Preferências `activity`, `push`; resposta inclui `pushAvailable`                                  |
| PUT `/me/push-devices/:id`                           | `{token}`, UUID de registro por sessão/instalação; desativado sem `PUSH_ENABLED=true`             |
| DELETE `/me/push-devices/:id`                        | Remove apenas registro pertencente ao usuário autenticado                                         |

O DTO compartilhado de comentários mantém o campo de transporte `reviewID`, que,
nas rotas `/posts`, contém o ID do post. Isso não cria vínculo com a tabela de reviews.
Posts retornam título/texto original; spoilers são revelados explicitamente no cliente.
A expansão da migration 016 acrescenta imagens, edição, menções, respostas, busca,
clubes, salas, teorias e duelos. Consulte o [contrato atual](live-community.md).
Reposts continuam ausentes.

Limites: título 140 caracteres, corpo 5.000, 10 posts/hora; comentários 2.000 e
30/hora somando posts/reviews; 120 alterações de reação/minuto por conta;
50 denúncias/dia somando todos os tipos. Conteúdo excluído ainda conta no limite.
Os limites são serializados pela trava transacional da conta. Bloqueios bilaterais,
autor em exclusão, denúncias pessoais e moderação valem na leitura e nas mutações.
A permissão de comentários segue `me/comment-permission`; `following` significa
pessoas que o autor segue. O autor pode comentar no próprio conteúdo.

CLI privada de moderação aceita `post`, `post_comment` e `club`, além de
`review` e `comment`. A fila mistura todos os tipos; decisões continuam auditadas.
Não existe triagem automática por IA nem painel administrativo nesta entrega.

## Notificações reais dentro do app

Eventos novos de seguir, comentar, responder, mencionar e reagir a reviews/posts/comentários geram
atividade na mesma transação da ação. Sem autoalertas. O índice único impede
alertas duplicados por retry ou alternância de reação/follow. Preferência desativada
impede novos eventos; não apaga o histórico. Eventos anteriores à migration não são
reconstruídos retroativamente. Seguir durante o onboarding não gera alertas.

A consulta revalida a visibilidade do alvo e do ator; bloquear, denunciar, moderar,
retirar a reação ou perder acesso ao conteúdo retira o evento da lista/contador.
Entrar na central não marca tudo como lido: toque em uma linha ou use “marcar estas”.
A ação envia IDs explícitos, preservando eventos que chegam depois. O botão confirma as notificações carregadas em lotes de até 100 IDs.
O toque abre o destino antes de aguardar essa confirmação: se ela falhar, a
navegação continua e o aviso permanece não lido. Posts/reviews abrem a conversa,
sem rolagem automática para comentários de páginas posteriores. Paginação e atualização manual disponíveis.
O sino atualiza ao abrir/voltar ao app e a cada 30 segundos em primeiro plano;
não há WebSocket/realtime nesta etapa. Cada conta tem store próprio e API vinculada
ao UID, inclusive após refresh do token. A abertura do conteúdo verifica novamente
as permissões na rota de destino.

## Push preparado, DESLIGADO

Decisão do usuário: ainda não possui Apple Developer; deixar preparado, sem tentar
criar chave/conta. Não foi enviada nenhuma notificação real nem alterada a configuração
Apple/Firebase. `PUSH_ENABLED` ausente equivale a `false`. Build padrão não contém
`aps-environment`, usa `MULTIVERSE_PUSH_ENABLED=NO` e desliga auto-inicialização FCM.
A central e o sino funcionam independentemente disso.

Código pronto: Firebase Messaging iOS 12.9.0, delegate SwiftUI, associação APNs→FCM,
consentimento, registro autenticado, renovação, limpeza no logout/exclusão, preferências,
outbox PostgreSQL e worker FCM. Tokens não são transferidos silenciosamente entre
contas; mudanças de sessão aguardam registros em andamento e invalidam o token antigo.
Se a limpeza falhar offline, a próxima conta precisa invalidar o token antes de registrar.
O payload não contém nome, título, texto ou spoiler; o toque abre a central da conta
atual, que consulta a API autorizada. Não navega diretamente por conteúdo do payload.

Worker: a cada 15s, até 10 eventos; `FOR UPDATE SKIP LOCKED` evita dois workers no mesmo
job. Revalida preferência, visibilidade e leitura. Expira eventos após 24h e registros
inativos após 60 dias. Até 5 tentativas, espera exponencial, remove tokens inválidos;
entregas aceitas são registradas por dispositivo para não reenviar aos já confirmados.
Sem dispositivos válidos, o evento não aguarda uma instalação futura. A entrega é
**pelo menos uma vez**: crash entre aceite FCM e commit pode repetir; collapse ID reduz
duplicação no sistema. Aceite FCM não é comprovação de exibição no aparelho.

### Ativar futuramente

1. Apple Developer ativo; registrar `com.nexussoft.multiverse` com Push Notifications
   e renovar o provisioning profile. Criar a chave APNs e guardá-la fora do repositório.
2. Firebase `multiverse-7f87c` → configurações → Cloud Messaging → app iOS: cadastrar
   chave `.p8`, Key ID e Team ID. Nenhuma chave privada vai para o app.
3. Verificar a API FCM e a permissão de envio da identidade Firebase Admin já usada
   no servidor; não substituir/duplicar credenciais sem necessidade.
4. Gerar a variante opt-in: `xcodegen generate --spec apps/ios/project-push.yml`,
   a partir da raiz do repo. Debug usa APNs development, Release usa production.
   O build padrão é restaurado com `xcodegen generate --spec apps/ios/project.yml`.
5. Configurar `PUSH_ENABLED=true` no serviço API apenas depois de concluir a configuração
   externa. Ajustes do app então oferece o opt-in quando servidor e build estão habilitados.
6. Validar em iPhone físico autorizado: permissão negada/aceita, app fechado,
   foreground, toque, token renovado, logout offline, troca de conta, bloqueio,
   revogação de acesso e retries. Ainda não realizado por falta de Apple Developer/APNs.

Referências oficiais: [Firebase Apple setup](https://firebase.google.com/docs/cloud-messaging/ios/get-started),
[Firebase Admin envio](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk).
O código segue as APIs da versão fixada no projeto, não APIs posteriores citadas em documentação atualizada.

## Validação

- API: formatação, lint, tipos, build, 72 testes unitários + 74 HTTP/PostgreSQL.
- Testes novos verificam posts, filtros/cursor, limites, propriedade, retries,
  moderação, bloqueio, contagem/leitura por conta, preferências, cascatas de exclusão
  e entrega/retry/expiração de push com provedor **simulado**, nunca tokens reais.
- iOS: suíte ampliada para 160 testes; build normal e variante opt-in compilados.
- Catálogo PT-BR/EN: 886 entradas verificadas.
- Não substitui teste manual com duas contas reais e iPhone provisionado.
