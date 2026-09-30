# Backlog — próximos passos sugeridos

Os caminhos de código abaixo são relativos a `apps/ios/`; as referências visuais ficam em `design/`.

Itens de produto/arquitetura que surgiram durante o desenvolvimento, avaliados e
conscientemente adiados (escopo grande demais pra entrar "de brinde" numa tarefa maior, ou
dependem de decisão de produto/design que não estava no escopo pedido). Nada aqui bloqueia o
app atual — é a lista do que fazer a seguir, em ordem sugerida de impacto.

## 1. Aba Arena (tirar Duelo/Debate da Home)

A Home hoje empilha: banner de escudo, grid de universos, clubes, trending, `DuelCard`,
`DebateCard`, teorias/previsões, feed, sugestões — está carregada. Proposta: criar uma 5ª
seção "Arena" (ou fundir com a aba Clubes, que já ganhou o slot livre na tab bar) reunindo
Duelo do dia, Debate, Previsões e Teorias — tudo que é "interação ativa" em vez de "consumo
passivo" de feed. A Home ficaria só com escudo + universos + clubes + feed + sugestões.

**Por que não entrou agora:** mexe na navegação central do app (`AppTab`, `CustomTabBar`,
`Navigation.swift`) e teria que ser decidido junto com o usuário qual ícone/posição — a tab
bar já foi reestruturada uma vez neste ciclo (Avisos → sino, slot livre → Clubes) e mexer de
novo sem alinhar era risco de idas e vindas.

## 2. Identidade visual

- **Capas ilustradas/reais** em vez do placeholder de cor chapada + halftone
  (`Logic.posterColors`). Precisa de um banco de imagens (licenciamento é o bloqueio real —
  Marvel/DC/Warcraft são IP de terceiros; capas fanmade ou geradas resolveriam sem risco).
- **Texturas por universo**: pergaminho pro Warcraft, big-dots pro DC, linework de traço pra
  Marvel — hoje os três usam o mesmo `Halftone()` component com cor diferente. Daria pra
  criar 3 variantes de textura em `DesignSystem/Halftone.swift` e escolher por `universe.id`.
- **Ícone do app e launch screen** — nenhum dos dois existe ainda (`project.yml` usa o
  ícone/launch screen padrão do XcodeGen). Precisa de arte final, não é algo pra gerar
  programaticamente.
- **Microinterações** além do burst atual (POW!/ZAP!/KRAK!) — ex.: confete ao completar uma
  ordem de leitura, animação de escudo abrindo ao revelar spoiler.

**Por que não entrou agora:** é trabalho de design visual (assets), não só código — pixel
fidelity aos screenshots fornecidos já foi o critério seguido à risca; inventar arte nova
sem referência do usuário seria a IA decidindo identidade visual sozinha.

## 3. Estados de erro/offline

`MockRepository` nunca lança erro (`catch` vazio em `AppStore.bootstrap()`, comentado
explicando isso). Um backend real vai falhar — timeout, 500, sem rede. Precisa de:

- `AppStore.loadError: String?` + tela de erro com "tentar de novo" na `RootView` quando
  `bootstrap()` falha.
- Estado de "sem internet" pros `Task { try? await repository.… }` espalhados pelo app (hoje
  o `try?` engole qualquer erro silenciosamente — funciona com mock, mas com rede real o
  usuário nunca saberia que uma ação não foi salva).
- Retry/fila local pras ações otimistas (curtir, votar, registrar) que falharem.

**Por que não entrou agora:** é o tipo de trabalho que só faz sentido depois que existe um
backend de verdade pra falhar contra — construir tratamento de erro pra uma API que ainda
não existe seria especulativo.

## 4. Missões guiadas da primeira semana

Ideia: um checklist leve pro onboarding pós-cadastro — "registre 3 obras", "vote num duelo",
"entre num clube" — com recompensa cosmética (badge, ou pontos de Lore/Previsão, sistemas que
já existem). Aumenta ativação sem ser intrusivo.

**Por que não entrou agora:** é uma feature de produto nova, não um recurso pedido no escopo
(Recursos/Interações) — precisa de decisão de quais missões e quais recompensas fazem
sentido, que é uma escolha de produto do usuário, não da implementação.

## 5. iPhone Duo (dobrável) — notas de adaptação

Sem specs oficiais da Apple ainda, então o que foi feito até aqui foi seguir princípios
gerais de layout adaptativo (Dynamic Type já cobre a maior parte, `GeometryReader` usado nos
pontos que precisam de posicionamento absoluto). Quando as specs saírem, os pontos a revisar
primeiro:

- `DuelCard`/`ItemView.topSection`: HStacks fixas que assumem uma largura de tela estreita —
  num dobrável aberto (mais largo), poster + info ficariam desproporcionais; candidatos a
  `ViewThatFits` ou breakpoint por `horizontalSizeClass`.
- `ExploreRoomsView`/`MessagesHomeView`: listas de uma coluna só — numa tela mais larga,
  dariam certo em grid de 2 colunas via `LazyVGrid` condicional.
- `LivePremiereView`: posicionamento de stickers via `GeometryReader` com coordenadas
  absolutas (`CGFloat.random(in: 40...330)`) — precisa virar relativo ao `geo.size` real em
  vez de faixa fixa, pra não ficar tudo colado num canto em tela mais larga.

## 6. SwiftData em `MockRepository`

Hoje `MockRepository` é um `actor` com tudo em memória (`var reviews: [Review]`, `var
messages: [Message]`, etc.) — só sessão de auth, onboarding e tema sobrevivem a um
relaunch (via `UserDefaults`, no `MockAuthRepository`/`AppStore.themePreference`). Tudo o
resto (reviews escritas, mensagens enviadas, progresso de sala, reações, votos) some ao
fechar o app.

**Plano concreto pra quando for implementar:**

1. Modelos `@Model` em `Core/Persistence/` espelhando os `struct` de `Models.swift` que hoje
   são só `Codable` — não substituir os `struct`, adicionar classes `@Model` paralelas só
   pros que precisam persistir mutação local (reviews do usuário, mensagens, diário,
   progresso de sala/clube, reações, votos). Catálogo (`Universe`, `Item`, `User` de outras
   pessoas) continua vindo do JSON read-only, não precisa de `@Model`.
2. `MockRepository` ganha um `ModelContainer`/`ModelContext` injetado no `init`, e os métodos
   que hoje só mexem em `var` in-memory (`postComment`, `sendMessage`, `postRoomMessage`,
   `setReaction`, `setRoomProgress`, `toggleLikedReview`, etc.) passam a persistir via
   `context.insert`/`context.save()` em vez de só mutar o array.
3. No `init`, em vez de sempre recarregar do zero a partir de `recursos-data.json`, checar se
   já existe dado persistido (`context.fetch`) e usar isso como estado inicial, caindo pro
   JSON só na primeira execução (seed).
4. Isso é 100% transparente pra `AppStore`/Views — a troca fica inteira dentro de
   `MockRepository`, que é exatamente o ponto de todo o desenho de repositório.

**Por que não entrou agora:** é uma migração de infraestrutura de dados que merece ser feita
isolada (não misturada com a entrega de 9 telas novas de Interações), e além disso alguns dos
tipos que precisariam virar `@Model` (`Message`, `RoomMessage`, `Conversation`) só foram
criados nesta última rodada — fazia mais sentido esperar o modelo de dados estabilizar antes
de decidir o que persiste e como.
