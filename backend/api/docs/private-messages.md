# Mensagens privadas

Conversas 1:1 persistidas no PostgreSQL, autenticadas pelo Firebase e vinculadas ao
UID da conta. Migration aditiva `020_private_messages.sql`. Não usa LiveKit: voz
continua exclusiva das salas e independente das mensagens privadas.

## Experiência e contrato

Acesso pelo envelope da Home, pelo perfil de outro usuário e pelo sino ao receber
uma mensagem. A caixa separa Conversas e Pedidos. A busca usa o diretório real de
pessoas. As telas usam o design system existente e strings PT-BR/EN.

- Texto de até 2.000 caracteres, carta de obra publicada e marcação explícita de spoiler.
- Se o destinatário segue o remetente, a conversa começa aceita. Caso contrário,
  permite uma primeira mensagem; só o destinatário pode aceitar ou recusar.
- Recusar oculta a conversa para ambos e impede novos pedidos daquele par. Ainda
  não existe recuperação de pedidos recusados. Bloquear pode ser revertido em Ajustes.
- O cliente escolhe UUID v4 por mensagem. Repetir o mesmo UUID/payload confirma o
  envio existente; trocar o conteúdo retorna conflito. Retry de resultado incerto
  mantém identidade/payload em memória. Não há fila offline durável depois de fechar o app.
- Leitura avança monotonicamente até a sequência que o cliente mostra no final da
  conversa aceita, em primeiro plano. Mensagens novas não são marcadas só por abrir a caixa.
- Sem presença online fictícia, afinidade, desafios privados, imagens, áudio ou grupos.

Rotas autenticadas sob `/api/v1/me/messages`, respostas `Cache-Control: no-store`:

| Método/rota                        | Operação                                                     |
| ---------------------------------- | ------------------------------------------------------------ |
| GET `/`                            | Caixa, total não lido e cursor `after` (30 conversas/página) |
| GET `/changes?after=revision`      | Long poll até 20 segundos                                    |
| GET `/:peer?before=sequence`       | Histórico, 40 mensagens/página, ordem crescente              |
| PUT `/:peer/messages/:uuid`        | Enviar `{kind,text,itemID?,spoiler}`                         |
| PUT `/:peer/request`               | Decidir `{accepted}`                                         |
| PUT `/:peer/read`                  | Ler até `{through: "sequence"}`                              |
| PUT `/:peer/messages/:uuid/report` | Denunciar `{reason,alsoBlock}`                               |

## Privacidade, concorrência e operação

Participantes precisam de conta ativa e onboarding concluído. Todas as leituras e
mutações verificam bloqueio bidirecional. Não é possível consultar uma conversa
entre terceiros. Exclusão da conta remove threads, mensagens, leituras e denúncias
relacionadas por cascade; notificações também deixam de ser acessíveis.

Um lock por par serializa a criação; lock da thread serializa sequência, envio e
leitura. Há limite durável de 120 mensagens/hora e 10 novas conversas/hora por
remetente. Retry confirmado não consome novamente o limite. Cartas não copiam o
catálogo: obra retirada vira uma carta indisponível, sem reintroduzir conteúdo arquivado.

Denunciar oculta a mensagem para o denunciante. Só a mensagem denunciada entra na
fila de moderação, não o histórico inteiro. A CLI privada aceita `--type message`;
a decisão auditada de ocultar substitui o conteúdo por mensagem indisponível.
O texto é armazenado no servidor; esta versão não oferece criptografia ponta a ponta.

Mensagens geram eventos no sino conforme preferências. A notificação push é genérica,
sem o texto privado. Push continua preparado e desativado até Apple Developer/APNs.

## Atualização e limites

Reutiliza o listener PostgreSQL LISTEN/NOTIFY das salas (um por instância da API),
com canal lógico por UID e revision persistida. O long poll não segura conexão de
pool por usuário. O iOS mantém um poll em primeiro plano; cancela em background,
reconecta com atraso progressivo e consulta só caixa/conversa ativa. O timeout de
20s também revalida permissões/perfis quando não houve evento. Histórico paginado,
lista preguiçosa, busca com debounce e compactação do histórico para as últimas 40 mensagens ao sair da conversa.

O backend persiste mensagens confirmadas entre dispositivos; rascunhos e retries
incertos vivem apenas na sessão do app. As atualizações não rolam à força quando o
usuário está lendo mensagens antigas: aparece o atalho de novas mensagens.

## Validação

- Suite HTTP/PostgreSQL: pedidos/aceite/recusa, terceiros, seguir, retries simultâneos,
  envios em sentidos opostos, paginação, leitura monotônica, bloqueio, catálogo,
  denúncia/moderação, eventos, exclusão, validação de payload e limites.
- iOS: identidade de retry, recibos inválidos, recuperação após resposta perdida,
  pedidos, paginação, resposta atrasada após envio, bloqueio, leitura, denúncia e contas.
- QA manual: duas contas em dispositivos/simuladores, iniciar pelo perfil/envelope,
  aceitar pedido, trocar texto/cartas, revelar spoiler, rolar histórico, reconectar,
  bloquear/desbloquear e testar PT-BR/EN. Entrega de push fechado depende de APNs.
