# Atualização — capas reais sem redesenho (03/10/2026)

- Pedido explícito: serviço completo de capas reais, preservando identidade visual.
- Importação Metron → fonte vinculada → API (catálogo/diário/feed) → cartões iOS.
  TMDB reutiliza posterURL. URLs HTTPS restritas; nenhum token no cliente.
- Migration 022 publica URLs de 30 edições e três filmes/séries já mapeados; obras
  sem vínculo conferido mantêm fallback. Não confundir edição com arco/encadernado.
- Imagens dentro das mesmas molduras; tamanhos, sombras, cores e navegação intactos.
  Cache HTTP/disco/memória, tarefas compartilhadas e thumbnail fora da main actor.
- Créditos PT-BR/EN distinguem metadados de direitos das imagens. Uso comercial
  ainda exige tratar condições/licenças dos provedores/titulares.
- Validação: 217 iOS, 93 unitários API, 131 HTTP/PostgreSQL, 1111 entradas PT-BR/EN;
  render de QA no simulador com imagens reais e componentes originais conferido.
- [Contrato, cobertura e atualização](../backend/api/docs/catalog-covers.md).

---

# Atualização — auditoria e estabilidade (03/10/2026)

- Corrigidos lotes de leitura de notificações, preferências e erros assíncronos
  atrasados, paginação durante refresh de inbox/alertas e recibos de leitura de DMs.
- Ordens preservam sucesso confirmado diante de erro antigo. Eventos de salas/DMs
  limpam conexões e watchers corretamente durante shutdown da API.
- Limpeza localizada de três stores; sem alteração de views ou contratos públicos.
- Validação: 213 iOS, 130 HTTP/PostgreSQL, 84 unitários API (83 no conjunto completo
  mais uma regressão posterior validada no arquivo), 14 Firebase; 1110 entradas PT-BR/EN.
  Formatação/lint/typecheck/build passaram; removida instabilidade temporal no teste
  de limite de reações, sem mudar a regra de produção.
- [Escopo, problemas, evidências e limites](CODE_AUDIT.md).
- QA manual segue pendente com o usuário; monetização adiada e push aguardando APNs.

---

# Atualização — ordens de leitura reais (03/10/2026)

Usuário autorizou implementar ordens de leitura e fará QA de mensagens/voz depois.

- Migration 021: percursos editoriais Marvel/DC em PT-BR/EN, passos ligados ao catálogo,
  seguir/votar reais, versões/recibos por UID e exclusão em cascata. API autenticada
  `/me/reading-orders`; conta ativa/onboarding, limites e conflitos entre dispositivos.
- Três percursos iniciais: Marvel (Fênix Negra → Guerra Civil → Guerras Secretas 2015),
  DC crises (Crise nas Infinitas Terras → Flashpoint), DC perspectivas (Watchmen →
  Reino do Amanhã). Seleções editoriais, não cronologia completa ou lista oficial.
- Reativada aba Ordens no universo com o layout existente. Contadores reais e autoria
  Multiverse. Seguidas primeiro; próxima leitura abre obra. Passos abrem diário, sem
  check paralelo; progresso conta IDs distintos do diário, ignora checks de onboarding.
- Ordem inteira oculta se etapa ficar indisponível. Não inventa substituições, não
  trata edição individual como volume inteiro. Estado privado é preservado no arquivo.
- Snapshot sob demanda/foreground, sem polling. Retry conserva UUID/payload; erros,
  cancelamento e conflitos não confirmam votos/follows no cliente antes do servidor.
- Validação: 81 testes unitários API, 130 HTTP/PostgreSQL, 205 iOS; 1110 entradas PT-BR/EN.
  Teste legado de limite de reações atravessou virada do minuto no conjunto e passou
  na reexecução isolada; nenhuma regra de produção de reações foi alterada.
- [Contrato, fontes editoriais e QA](../backend/api/docs/reading-orders.md).
- Próximos passos: QA manual acumulado (ordens/DMs em duas contas, voz em iPhones),
  depois ampliar catálogo e curadoria por personagem/edição. Monetização segue adiada;
  push aguarda Apple Developer/APNs. Ordens comunitárias ainda não implementadas.

---

# Atualização — mensagens privadas reais (03/10/2026)

Pedido ativo concluído: mensagens privadas, preservando estilo/PT-BR/EN e prioridade
em performance. Monetização permanece adiada pela decisão abaixo.

- Migration 020, módulo `messages`, API autenticada para caixa/histórico/envio,
  pedidos/aceite/recusa, leitura, denúncia e long poll. Conta excluída remove os DMs.
- Uma mensagem inicial para quem não segue o remetente; após aceite, conversa normal.
  Recusa não pode ser recuperada nesta versão. Bloqueio bidirecional e limites duráveis.
- UUID por mensagem e payload preservado no retry, sequência/leitura monotônicas,
  notificações sem corpo privado, fila administrativa só para conteúdo denunciado.
- iOS: envelope Home, botão no perfil e destino no sino; busca real de pessoas,
  texto/cartas/spoiler, estado de leitura, paginação e novos eventos sem forçar rolagem.
  Sem presença/afinidade falsa. Poll só foreground; LiveKit permanece separado.
- Validação: 81 unitários API, 120 HTTP/PostgreSQL, 196 iOS; 1095 entradas PT-BR/EN.
  [Contrato e QA de duas contas](../backend/api/docs/private-messages.md).
- Ainda fora desta entrega: fotos/áudio/grupos/editar-apagar mensagens e fila offline
  durável. Desafios por DM continuam demo oculta. Push continua aguardando APNs.
- Próximos passos: QA de DMs em duas contas e voz em iPhones; depois catálogo editorial
  (ordens de leitura reais). Monetização só retomar sob novo pedido. Inventário completo
  em [DEMONSTRATION_INVENTORY.md](DEMONSTRATION_INVENTORY.md).

---

# Decisão — monetização adiada (03/10/2026)

Lucas pediu documentar RevenueCat e afiliados e deixar a implementação para análise
posterior. **Não é uma tarefa ativa; aguardar nova solicitação para retomar.**
Levantamento, arquitetura proposta, pendências e fontes estão no
[backlog de monetização](BACKLOG.md#monetização--adiada-por-decisão-do-usuário-03102026).
Nenhuma integração de monetização foi implementada nesta etapa.

---

# Atualização — escopo Marvel e DC (03/10/2026)

- Produto limitado a Marvel/DC. Retirados os demais universos do onboarding,
  fixtures PT-BR/EN, widgets, sugestões, ordens, conexões e exemplos de comunidade.
- Cartões de universo seguem o HStack com larguras flexíveis iguais (agora dois).
  Tipografia, navegação e cores preservadas; amarelo renomeado de wow para accent.
  Grids de obras continuam com três colunas: não representam universos.
- Migration aditiva 019 arquiva universos/itens fora do escopo, filtra preferências
  antigas e incrementa sua versão. Não apaga histórico nem reinicia contas concluídas.
  Diário privado mantém obras Marvel/DC arquivadas, mas não reintroduz universos retirados.
- Validação: 81 testes unitários API, 108 HTTP/PostgreSQL e 184 iOS; 1060 entradas
  localizadas. Inclui migração de preferências antigas e referências PT-BR/EN.
- Migrações anteriores e design de referência são históricos; não são conteúdo ativo.
- Próximo pedido: levantamento de RevenueCat e monetização por afiliados. Usuário
  criou um paywall no RevenueCat, mas ainda não forneceu offering/projeto. Código
  atual usa StoreKit 2 diretamente; Onde assistir é mock e oculto em sessões reais.
  Pediu avaliar entidade oferta/edição e redirecionamento por backend, regras de
  parceiros e viabilidade, antes de integrar. Não foi implementado nesta entrega.

---

# Atualização — voz LiveKit nativa nas salas (03/10/2026)

Usuário autorizou integrar voz, sem vídeo, com UI discreta, performance e fluidez.
Forneceu credenciais LiveKit Cloud; configuradas no .env ignorado e no Railway por
stdin, sem exposição no código/Git. Rotação será posterior por decisão do usuário.

- Botão VOZ e sheet nativa recolhível sobre o chat, preservando abas/design system.
- SDK só conecta ao entrar; microfone desligado até ação explícita e permissão.
  Ouvintes sem permissão continuam ouvindo; participantes/fala por eventos do SDK.
- Até 8 pessoas por obra/trecho. Voz termina ao sair da tela, trocar trecho ou ir ao
  background. Chat segue independente. Sem vídeo, gravação, palco/anfitrião ou pedir fala.
- API autoriza Firebase/conta/onboarding/obra/progresso e bloqueios. JWT 60s só para
  microphone; UUID opaco de sessão; 1 sessão por conta e 30 entradas novas/hora.
- Migration aditiva 018; lease 60s renovada a cada20s, limpeza de inválidos a cada15s.
  Perfil/obra apagados ainda permitem desconectar a mídia. Desligamento por VOICE_ENABLED.
- Testes: 81 unitários API + 106 HTTP/PostgreSQL +184 iOS; PT-BR/EN1060 entradas.
  Dois clientes WebRTC reais trocaram áudio sintético no projeto; sala de teste removida.
  Microfone físico/Bluetooth/interrupções no iPhone ainda precisam de QA em dispositivos.
- [Contrato, operação e limites](../backend/api/docs/voice-rooms.md).

Os registros abaixo são históricos.

---

# Atualização — salas com eventos e composer (03/10/2026)

- Sheet de criar/editar posts com design system, thumbnails/remover, menções/spoiler
  e publicar fixo acima do teclado. Mantidas regras de envio, imagens e retry.
- Salas: long polling autenticado acordado por LISTEN/NOTIFY do PostgreSQL, revision
  durável na migration aditiva 017. Sem mensagens nos avisos; conteúdo sempre relido
  pelas regras existentes. Timeout de 20s renova presença e revalida visibilidade;
  cliente reconecta com recuo 1–20s. Uma conexão de escuta por instância da API.
- Mensagens cronológicas, abertura no fim, histórico acima, aviso de novidades sem
  puxar a leitura, cache de novas mensagens e descarte de resultados de outro trecho.
- Progresso em sheet com slider e atalhos 0/50/100; limites de spoiler no backend.
- Verificação: 78 unitários API, 102 HTTP/PostgreSQL, 181 iOS, 1040 entradas PT-BR/EN.
  Banco de teste descartável `multiverse-rooms-test`; nenhuma fixture em produção.
- Mudanças locais preexistentes de formatação no catálogo e espaço em MockRepository
  foram preservadas. Commit do catálogo inclui apenas as seis novas entradas traduzidas.
- WebRTC foi solicitado como **mapeamento após esta entrega**, não implementação.
  Não adicionar SDK nem contratar serviço até o usuário pedir essa etapa.
  Proposta: sala de voz por obra/trecho, participantes e anfitrião, entrar/sair,
  microfone, pedir fala, silenciar/remover. Chat persistido continua na API atual.
  `LiveRoomView` hospedaria controles; um store separado gerenciaria áudio/conexão;
  API NestJS validaria Firebase, obra/progresso e papel antes de emitir token curto;
  um serviço de mídia SFU/TURN, como LiveKit Cloud, distribuiria o áudio.
  Hoje não há SDK WebRTC, permissão de microfone ou moderação de sessões de voz.
  Fonte oficial: https://github.com/livekit/client-sdk-swift e
  https://docs.livekit.io/transport/self-hosting/deployment/.
- Push/APNs permanecem desligados; WebRTC em primeiro plano é uma etapa separada.

Os registros abaixo são históricos.

---

# Atualização — Comunidade dinâmica (02/10/2026)

Usuário autorizou edição/imagens, respostas/menções, busca/descoberta e módulos reais
para clubes, salas, teorias e duelos. Implementado com migration aditiva 016.

- Posts: edição com versão/idempotência; até quatro imagens verificadas por Sharp,
  JPEG sem metadados; armazenamento PostgreSQL privado e leitura autenticada.
- Respostas vinculadas ao comentário pai e menções por @handle/seletor; eventos reais
  no sino. Visibilidade revalidada para bloqueio, denúncia, moderação e exclusão.
- Busca textual; filtros recentes/seguidos/em conversa e universo/obra/tipo.
- Clubes públicos: CRUD, membros, calendário por obra/data, progresso por membro/etapa,
  discussões e convites com deep link; denúncias na CLI auditada existente.
- Salas por obra publicada: mensagens/respostas/imagens, presença com TTL de um minuto,
  atualização a cada 10s em primeiro plano e progresso persistido; trechos 0/50/100
  protegidos no servidor, inclusive imagens e notificações.
- Teorias: votos reais e conclusão do autor explicitamente rotulada. Duelo: duas
  opções, prazo e voto único por conta com alteração. Nada de números por seed.
- Novos módulos acessados pela Comunidade; sala também na ficha da obra. Layout da
  barra/Biblioteca preservado. As telas legadas de demonstração continuam isoladas.
- Validação: 75 unitários + 100 HTTP/PostgreSQL API; 178 iOS; 1034 entradas PT-BR/EN.
  Fixtures HTTP agora mantêm uma porta por suíte para evitar races de bind/close
  de Supertest em requisições concorrentes. Sem relaxar autorização/assertions.
- Push continua desligado. Sem Apple Developer/APNs; não habilitar nesta entrega.
- Sem reposts, vídeo, DMs, live de estreia, ranking de afinidade ou IA de confirmação.
  Moderação ainda é CLI; salas usam polling. Imagens no PostgreSQL têm limites;
  object storage/CDN deve preceder escala ampla de mídia.
- [Contrato e limites](../backend/api/docs/live-community.md).
- [Inventário atualizado](DEMONSTRATION_INVENTORY.md).

Os registros abaixo são históricos.

---

# Atualização — séries completas e ajustes da Biblioteca (02/10/2026)

O usuário aprovou expandir as quatro séries Metron e organizar edições por número.
Durante o trabalho, pediu preservar o layout e ajustar especificamente os estados
vazios de Quero consumir, Favoritos e Listas, além da quebra do rótulo Biblioteca.

- 30 edições revisadas: Guerra Civil 1–7, Dinastia M 1–8, Guerras Secretas 1–9,
  Desafio Infinito 1–6. IDs #1 e sagas preexistentes preservados.
- PT-BR adaptado editorialmente a partir das descrições reais, EN da Metron.
  Descrições curtas da fonte permanecem curtas, sem conteúdo inventado.
- Migration `015_catalog_series.sql`: séries/traduções/vínculos; metadados `series`
  compartilhados entre catálogo, diário e feed. Sem segredo ou chamadas externas no iOS.
- Publicação Metron busca 30 edições com 3,1s entre chamadas e grava tudo em uma
  transação. Prévia manual permanece limitada a 10 IDs; não buscar lotes em paralelo.
- iOS: seção/tela de série, ordem numérica e progresso de obras distintas no diário.
- Biblioteca: fonte/cores/cartão do design system nos estados vazios, sem alterar
  filtros, ações, estrutura ou posição das abas. Rótulos em uma linha com escala
  de texto; dimensões da tab bar e botão central preservadas.
- Validação: 75 unitários + 88 HTTP/PostgreSQL, 170 iOS, 938 entradas PT/EN.
  PostgreSQL descartável desta rodada: multiverse-series-test, localhost:55433.
- Credencial Metron já configurada; nunca imprimir. Push continua desligado.
- [Guia operacional e limites](../backend/api/docs/marvel.md).

Registros abaixo são históricos.

---

# Atualização — Metron ativa (02/10/2026)

Usuário forneceu token e autorizou implementar, preservando PT-BR/EN. Credencial
configurada no `.env` ignorado e nas variáveis privadas de `api`/production Railway.
Não copiar o valor para documentação, código ou respostas. Rotação fica para depois,
conforme solicitado; basta substituir METRON_API_TOKEN nos dois locais.

- Respostas reais validadas para 3726, 21884, 27065 e 42511 (#1 das quatro séries).
- Corrigidos publisher Marvel/ID 1 e nome The Infinity Gauntlet no conector.
- Migration `014_metron_published_sources.sql`; publicação transacional operacional
  via `node scripts/preview-marvel-sources.mjs --provider=metron --publish`.
- Obras próprias `m-metron-issue-<ID>`; nunca substituir os IDs das sagas existentes.
- PT-BR editorial adaptado e EN da fonte; sem tradução automática ou sinopse inglesa
  marcada como portuguesa. Fonte/licença/adaptação creditadas em Ajustes e nas obras.
- Não fornece páginas da HQ: só metadados para descoberta, diário e biblioteca.
- Testes: API 73 + 87; iOS 167; idiomas 926. [Guia](../backend/api/docs/marvel.md).
- Push permanece desligado; Apple Developer/APNs continuam pendentes.

Os registros abaixo são históricos.

---

# Atualização — Biblioteca pessoal (02/10/2026)

O usuário aprovou desejos/favoritos persistidos, listas pessoais reais e ocultação
dos módulos demonstrativos. Biblioteca substitui Clubes na barra principal.

- Migration `013_personal_library.sql`: estado por conta, marcações, listas e recibos
  de mutação. Importa uma vez os favoritos do último registro de cada obra no diário.
- `GET/PUT /me/library`: privado, exige conta verificada/onboarding; versionamento,
  recibos idempotentes, limites e exclusão em cascata com a conta.
- iOS: biblioteca, edição/exclusão de listas, seletor de obras, coração/desejo reais,
  estados vazios/erro/retry. Sem gravação otimista ou fila offline durável.
- Rotas/atalhos demo ocultos na sessão real; widgets não publicam amostras. O código
  legado foi preservado. Push continua preparado e desligado, sem Apple Developer.
- Validação: 167 testes iOS, 72 unitários + 85 HTTP/PostgreSQL API, 923 entradas PT/EN.
- [Contrato da Biblioteca](../backend/api/docs/library.md) e
  [inventário atualizado](DEMONSTRATION_INVENTORY.md).
- Testes deste lote usam PostgreSQL descartável `multiverse-library-test`, porta 55433.
  Não substituir pelo banco de produção. Homologação manual com duas contas ainda pendente.

Os registros abaixo são históricos; estado e limitações atuais estão acima e no inventário.

---

# Atualização — posts e notificações (02/10/2026)

Itens 2 e 3 autorizados pelo usuário foram implementados: posts de texto ligados a
universos/obras, comentários/reações, denúncias/bloqueio/exclusão; central de atividade,
leitura e sino reais. O usuário pediu push com app fechado, mas depois informou que
não possui Apple Developer e autorizou deixá-lo preparado. Não criar conta/chave agora.

- Migration nova: `012_community_notifications.sql` (não alterar após deploy).
- API: 72 unitários + 74 HTTP/PostgreSQL; iOS: 160; idiomas: 886 PT/EN.
- Push: `PUSH_ENABLED=false` por padrão; build comum sem entitlement APNs.
  Variante `apps/ios/project-push.yml`, iOS FCM e worker preparados e compilados.
  Nenhuma entrega APNs real testada. Provedor de envio simulado nos testes.
- Guia: [comunidade/notificações](../backend/api/docs/community-notifications.md).
- Lista completa de limitações: [DEMONSTRATION_INVENTORY.md](DEMONSTRATION_INVENTORY.md).
- Não confundir posts novos com as telas antigas de teorias, duelos, salas e clubes;
  estas continuam usando demonstrações, conforme o inventário.
- Testes usam PostgreSQL descartável `multiverse-community-test` em localhost:55433.

O registro abaixo documenta o lote anterior de recuperação/comentários de reviews.

---

# Retomada do Multiverse — 02/10/2026

## Objetivo recuperado

A sessão anterior terminou a entrega `bf852c8` (feed real, privacidade, denúncias
e bloqueios) e publicou esse commit no Railway. O histórico local confirmou a
autorização seguinte: implementar comentários e reações reais, respeitando
“Quem pode comentar”, mais revisão administrativa de denúncias. A sessão foi
interrompida antes de implementar essa etapa. Este lote conclui esse recorte.

O usuário autorizou finalizar, validar e fazer push. Layout, componentes e PT-BR/EN
devem ser preservados. A proposta futura de comunidade semelhante a fóruns não
autoriza reorganizar a navegação, trocar identidade visual ou abrir posts livres
sem definir o próximo recorte.

## Mapa do app

SwiftUI/iOS 17+, Swift 6, XcodeGen e widgets. `RootView` injeta os clientes reais
em `AppStore`, `PeopleStore` e `SocialStore`. Firebase cuida da identidade;
NestJS/PostgreSQL cuidam da conta e dos dados sociais. `MockRepository` ainda
fornece módulos do protótipo; sua presença não significa que o app todo seja mock.

| Área | Estado |
| --- | --- |
| Google/e-mail, perfil, @usuário, onboarding e exclusão | Implementados; Firebase + API |
| Catálogo e busca | PostgreSQL, PT/EN; acervo inicial limitado |
| Marvel externo | Wikidata e TMDB integrados; Metron preparado e aguardando credencial/cadastro |
| Diário, notas e reviews pessoais | Persistidos, com estados vazios, falhas e retry |
| Pessoas, perfis, seguir/deixar de seguir | API real, contadores e bloqueios |
| Feed, privacidade e denúncias | Reviews reais, opt-in, paginação e proteção |
| Comentários e reações | Este lote; permissões, limites e persistência reais |
| Revisão de denúncias | CLI privada, decisões auditadas; sem IA ou painel web |
| Clubes, salas, mensagens, teorias, previsões, duelos | Ainda contêm dados/interações de demonstração |
| Listas, desejos, conexões e cronologias | Ainda precisam de revisão/migração por fluxo |
| Wrapped/presença | Mistos/estáticos; central de notificações substituída no lote descrito acima |
| Pro | StoreKit implementado; vínculo à conta Multiverse e validação backend pendentes |

## Alterações locais recuperadas

Havia arquivos sem commit antes desta retomada: template de e-mail PT/EN e envio
do locale; ajuste de espaço da tab bar; preparação Docker/Railway; notas de setup;
entradas de localização extraídas pelo Xcode. Foram preservados e revisados.
As funções de e-mail já tinham registro de publicação; não foi necessário
reenviar e-mails ou mexer em DNS/faturamento.

O verificador de idiomas falhava em 53 entradas automáticas sem cobertura PT/EN.
As entradas foram completadas e `SWIFT_EMIT_LOC_STRINGS=NO` mantém a gestão pelo
`L10n`, sem novas extrações automáticas. READMEs antigos diziam incorretamente que
catálogo, diário e feed ainda eram somente mock; foram atualizados.

## Validação e infraestrutura

- API: formatação, lint, tipos, build, 72 testes unitários e 59 testes HTTP com
  PostgreSQL local, incluindo os casos novos de interação/moderação.
- iOS: build e suíte de 150 testes; catálogo de idiomas verificado pelo script.
- Firebase: 14 testes locais. Não enviam e-mail nem alteram o projeto Firebase.
- PostgreSQL de teste: container isolado `multiverse-interactions-test`, porta
  local 55433. Os testes criam/removem schemas próprios; não usam produção.
- Railway: serviço `api`, projeto `multiverse`, ambiente `production`, GitHub
  `zUnknownUser/Multiverse`, branch `master`, raiz `/backend/api`; predeploy
  `npm run db:migrate` e healthcheck `/api/v1/health`.
- Nova migration: `011_review_interactions.sql`. Não editar depois de publicada.

## Pendências reais

1. Teste manual de ponta a ponta com duas contas, incluindo cadastro/código,
   reenvio, recuperação por link em aparelho e interações sociais. Testes usam
   autenticação injetada; não substituem essa validação.
2. Acompanhamento humano da fila de denúncias; depois definir painel, comunicação
   ao autor e contestação antes da expansão para posts livres/reposts.
3. IA está preparada no backend, mas não está moderando conteúdo automaticamente.
4. Metron continua adiado conforme decisão do usuário. Não trocar outros domínios
   ou integrações para tentar contornar essa dependência.
5. Rotação da chave de envio Resend mencionada no histórico como compartilhada;
   detalhes operacionais em `backend/firebase/PENDING_SETUP.md`, sem segredos.
6. Antes do lançamento: migrar/ocultar módulos de demonstração conforme decisão
   de produto, rever notificações e Pro, paginar diário/carga inicial do catálogo,
   definir monitoramento/readiness e limites gerais de produção.

Contrato e operação desta etapa: [interactions.md](../backend/api/docs/interactions.md).
Backlog de produto: [BACKLOG.md](BACKLOG.md); suas propostas históricas não são
uma autorização automática para redesenhar o app.
