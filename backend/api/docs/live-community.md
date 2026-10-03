# Comunidade dinâmica

Implementação de 02/10/2026; migration aditiva `016_live_community.sql`.
Todos os endpoints abaixo exigem Firebase ID token, conta ativa e onboarding concluído.
Conteúdo escrito por usuários preserva o idioma original; interface/erros em PT-BR e EN.

## Posts, mídia e conversas

- `GET /posts`: filtros `q` (até 120 caracteres), `universe`, `item`, `kind`, `club`,
  `schedule`, `segment`, `feed` e `after`. Página de 30 com cursor `(created_at,id)`.
  `feed=recent` mostra recentes; `following`, autores seguidos; `active`, posts dos
  últimos sete dias com comentários visíveis. **Não é ranking personalizado**.
- `PUT /posts/:id`: UUID v4 estável do cliente. Campos anteriores + `kind`
  (`discussion`, `theory`, `duel`, `room`), `imageIDs` (até 4), `clubID`, `scheduleID`.
  Duelo exige `optionA`, `optionB` diferentes (até 120 caracteres) e `closesAt`
  entre agora e 30 dias. Sala exige obra publicada e `segment` (0, 1, 2).
- `PATCH /posts/:id`: `{title,text,spoiler,imageIDs,version,mutationID}`. Apenas autor;
  optimistic concurrency; retry da mesma mutação confirma sem sobrescrever outro
  dispositivo. Não troca universo/obra, opções de duelo ou escopo depois de publicar.
- `PUT /posts/:id/images/:imageID`: `{base64}`, entrada JPEG/PNG/WebP até ~2 MB,
  até 20 MP. Sharp reencoda para JPEG de até 1600 px / 1 MiB, sem metadados originais.
  Até 20 imagens/hora e 100 MiB armazenados/conta. UUID e hash protegem retries/reuso.
  Bytes ficam no PostgreSQL, em tabela separada, **não no filesystem efêmero Railway**.
  Não é um CDN; migrar bytes para object storage antes de ampliar essa carga.
- `GET /posts/:id/images/:imageID`: JSON com base64; mesma autorização/visibilidade
  do post, `no-store`. Não aceita URL externa. Spoilers não carregam imagens antes
  de revelados. Anexos sem post após 24h são coletados por hora e durante uploads;
  a coleta pula imagens bloqueadas por uma publicação em andamento.
- Comentários aceitam `parentID` opcional, validado no mesmo post e visível ao autor
  da resposta. A lista continua paginada cronologicamente, com referência ao pai;
  o cliente identifica/recua respostas. Não é uma árvore ilimitada carregada de uma vez.
- `@username` resolve perfis existentes, com seletor de pessoas no app. Até 10 por
  texto; menções e respostas geram eventos `mention`/`reply` na central. Bloqueios,
  denúncias, moderação, exclusão e retirada da menção são revalidados ao ler o evento.
- Posts normais: 10/h; mensagens de sala: 60/h, cotas independentes. Comentários:
  30/h somando reviews/posts. Imagens e menções não permitem enviar como outra conta.

## Clubes

Acesso por Comunidade → Clubes. Clubes públicos, com entrada voluntária; criar,
listar/buscar, editar/excluir pelo organizador, entrar/sair, membros paginados,
calendário por obra/data, progresso por pessoa/etapa e discussões por clube/etapa.

- `GET /community/clubs?q=&universe=&after=` e `GET /community/clubs/:id`.
- `PUT /community/clubs/:id`: `{name,description,universeID,version?}`; editar usa versão.
- `DELETE /community/clubs/:id`: encerra e oculta o clube e suas conversas.
- `PUT /community/clubs/:id/membership`: `{joined}`; organizador não pode abandonar
  o próprio clube (pode encerrá-lo). Até 200 participantes e 20 clubes criados/conta.
- `PUT /community/clubs/:id/schedule/:id`: `{itemID,startsOn,totalUnits,unitLabel}`;
  datas reais, obra publicada no universo, até 52 etapas, data única por clube.
  `DELETE` na mesma rota remove a etapa, seu progresso e discussão vinculada.
- `PUT .../schedule/:id/progress`: `{units}`, de zero ao total. Só membros.
- `GET .../members?schedule=&after=`: somente membros; autores bloqueados são omitidos.
- `PUT .../report`: `{reason,alsoBlock}`; desaparece para o denunciante, incluindo posts.
  Moderação CLI também aceita `club`; esconder impede acesso/edição ao clube e posts.
- Convite usa compartilhamento nativo de `multiverse://club/UUID`. O link abre o
  clube após login/onboarding, **não inscreve alguém automaticamente**.

Sem cutucada fictícia, pontuação por seed ou membros de exemplo. Não há convite por
push, coorganizador, expulsão individual, transferência de propriedade ou clube privado.
Apagar a conta organizadora remove os clubes de sua propriedade por cascata.

## Salas

Comunidade → Salas e atalho na ficha da obra. Cada obra publicada tem uma sala;
nenhuma criação editorial ou amostra é necessária.

- `GET /community/rooms?q=&universe=&after=`: obras/salas paginadas e presença real.
- `PUT /community/rooms/:item/visit`: `{progress?}`, preserva progresso quando omitido.
  Presença considera visitas no último minuto, com filtros de conta ativa/bloqueios.
- Mensagens são posts `kind=room`, fora do feed global. Carregamento inicial de 30;
  páginas anteriores por cursor. Abrir mensagem permite respostas, reação e denúncia.
- `GET /community/rooms/:item/changes?after=<revision>`: long polling autenticado,
  acordado imediatamente por PostgreSQL LISTEN/NOTIFY após commit. Sem alteração,
  responde em até 20s para renovar presença e acesso. Resposta contém somente
  `itemID`, `online`, `progress` e `revision` (string); nunca mensagens/spoilers.
  Revisão durável recupera eventos perdidos. Uma conexão LISTEN por instância da API;
  no máximo três esperas simultâneas por conta; cancelamento desconecta a espera.
  Migration aditiva `017_room_realtime.sql`; inserção/edição/exclusão de mensagens
  altera a revisão transacionalmente, inclusive operações da moderação.
- iOS acompanha alterações enquanto ativo e reconecta com recuo de 1 até 20s.
  A leitura autorizada dos posts continua separada. Presença mantém TTL de um minuto.
  Os heartbeats também revalidam visibilidade, inclusive bloqueios e progresso.
- Conversa em ordem cronológica, abrindo nas mensagens mais recentes. No histórico,
  novas mensagens são guardadas até tocar no aviso; atualizações não puxam a tela.
  Páginas antigas carregam acima e preservam a mensagem que estava sendo lida.
- Progresso ajustável por slider de 10 em 10 e atalhos 0/50/100, com confirmação.
  A sheet de criar/editar também usa agora os cards/tipografia do app e rodapé fixo.
- Trechos Geral / Até a metade / Final exigem progresso 0 / 50 / 100, respectivamente.
  A API verifica o progresso na publicação e leitura, incluindo imagens/notificações.
  O progresso é autodeclarado e sincronizado; não é reconhecimento de leitura.
- Não inclui DMs, digitação, entrega/leitura por destinatário, estreia ao vivo ou WebSocket.

## Teorias e duelos

Comunidade → Teorias/Duelos reutiliza a infraestrutura moderável de posts.
`PUT /posts/:id/vote {choice:0|1}` conta **um voto por conta**; trocar voto atualiza o
mesmo registro. Contagens vêm do banco e respeitam bloqueios/contas removidas.

Teorias usam Plausível/Viajou. Autor pode registrar/reabrir conclusão com
`PUT /posts/:id/resolution {status,note,version}`; `confirmed`/`refuted` exigem explicação
(até 1.000 caracteres). Interface declara **conclusão do autor**, sem inventar verificação
editorial, fonte automaticamente validada, pontos ou precisão. Teoria resolvida não
recebe novos votos até reabertura.

Duelos: pergunta/título, contexto, duas opções, prazo real. Voto novo ou alteração
após encerramento falha; retry de voto já salvo confirma. Sem votos-base, vencedores
fictícios, aposta, DM de desafio ou “duelo do dia” escolhido automaticamente.

## Moderação, operação e limites

Reutiliza denúncias, bloqueios e CLI auditada; mídia é ocultada junto do post.
A CLI não é painel visual de moderação e não classifica imagens automaticamente.
Não há reposts, busca personalizada por algoritmo, fila offline durável ou upload de vídeo.
As telas antigas/fixtures em `MockRepository` continuam apenas nos previews/demo, sem
atalhos na sessão autenticada. A barra principal/Biblioteca não foi redesenhada.

Push permanece **desligado**, conforme pedido; menções/respostas funcionam no sino.
[Ativação futura APNs](community-notifications.md). Token Metron permanece privado e
não é utilizado nesses endpoints. Nenhum conteúdo de teste deve ser semeado em produção.
