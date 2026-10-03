# Backlog — próximos passos sugeridos

## Monetização — adiada por decisão do usuário (03/10/2026)

**Status: somente levantamento.** Lucas decidiu documentar RevenueCat e afiliados
para analisar depois. Não implementar, ativar programas, contratar serviços ou
alterar o paywall até uma nova solicitação. Não há prazo definido para retomada.
O escopo atual do produto permanece Marvel e DC, com o visual e PT-BR/EN preservados.

### Estado atual e RevenueCat

- O app usa StoreKit 2 diretamente em `Core/Store/ProStore.swift` e apresenta
  `Features/Pro/ProPaywallView.swift`. RevenueCat ainda não está integrado.
- O usuário criou uma tela no RevenueCat, mas seu projeto, offering, entitlement
  e configuração visual ainda não foram inspecionados.
- Possível integração futura: SDK RevenueCat/RevenueCatUI, paywall vinculado à
  offering, identidade alinhada ao Firebase e acesso Pro confirmado por entitlement.
  Definir uma única autoridade para compras/restauração e, se necessário, sincronizar
  permissões do backend por webhooks validados. Evitar dois fluxos de compra concorrentes.
- Test Store permite testar sem conectar a App Store. Vendas reais no iPhone dependem
  da conta Apple Developer, produtos e configuração no App Store Connect.
- RevenueCat atende às assinaturas Pro; comissões de lojas pertencem ao módulo de afiliados.

### Proposta de ofertas — ainda não implementada

Fluxo proposto pelo usuário: obra → opções em “Onde encontrar” → clique no backend
(`/out/{offerId}`) → loja → eventual comissão pela conversão qualificada.

- Separar **obra**, **edição/produto** e **oferta comercial**. O catálogo atual não
  garante correspondência automática com a edição vendida. Vincular ISBN/EAN,
  editora, idioma, formato e identificador externo; revisar correspondências ambíguas.
- `CommerceOffer`: ID estável, obra/edição, provedor, produto externo, formato,
  preço opcional, moeda, país, disponibilidade, última verificação e condição de afiliado.
  Preço monetário deve preservar precisão. País/moeda independem do idioma do app.
- Backend mantém credenciais e regras de destino. O app recebe dados de exibição e
  ação de abertura. Tags de afiliado podem aparecer na URL final; não são segredos de API.
- Redirecionamento apenas quando permitido pelo parceiro. Para abertura direta,
  medir o clique separadamente, sem bloquear a navegação por falha de telemetria.
  Restringir destinos a ofertas cadastradas e domínios autorizados.
- Carregar ofertas da nossa API/cache, atualizar fora do caminho de abertura da obra
  e ocultar preço vencido ou sem fonte autorizada (“Ver preço na loja”). Sem scraping
  indiscriminado ou promessa de busca automática em todas as lojas.
- Clique não confirma venda: conversões e comissões dependem dos relatórios ou
  integrações do parceiro, incluindo cancelamentos e devoluções.
- `Features/Item/WhereToWatchSection.swift` é demonstrativo, oculto em sessões reais,
  e ainda não realiza compras. Reaproveitar seu estilo para “Onde encontrar”, com
  indicação de afiliado e sem exigir Pro para acessar links da Amazon.

### Dependências identificadas no levantamento

| Parceiro/tema | Situação a revalidar na retomada |
| --- | --- |
| Amazon | Exige aprovação do app; orienta evitar redirecionadores e abrir no app Amazon/navegador externo. Preços e disponibilidade exigem fontes autorizadas. Não presumir que `/out` sirva para todos os parceiros. |
| Mercado Livre | Programa existe; documentação consultada lista redes sociais, sites e blogs cadastrados. Aceitação de um app como o Multiverse ainda precisa ser confirmada. |
| Panini Brasil | Não foi confirmado programa oficial adequado à integração. Prever ofertas sem comissão até comprovar parceria. |
| Apple Books | Programa existe, com admissão seletiva; participação não está garantida. |
| Produtos digitais | Avaliar regras da App Store por região para Kindle, ebooks, streaming e outros conteúdos digitais. Não tratar como equivalentes a produtos físicos. |
| TMDB | Verificar licença comercial antes de monetizar; a modalidade gratuita documentada é para uso não comercial. Não presumir que a chave atual autorize monetização. |

**Possível primeira etapa, sujeita a nova decisão:** poucas edições físicas
verificadas, ofertas reais, abertura da loja e medição de cliques; RevenueCat em
ambiente de teste. Ativar comissões somente após aprovação dos respectivos canais.
Não há garantia de receita ou de aprovação dos parceiros.

### Fontes consultadas em 03/10/2026

Revalidar políticas, disponibilidade e requisitos antes de implementar:

- [RevenueCat: apresentação de paywalls](https://www.revenuecat.com/docs/tools/paywalls/displaying-paywalls)
- [RevenueCat: Test Store e conexão das lojas](https://www.revenuecat.com/docs/projects/connect-a-store)
- [Amazon: aplicativos móveis](https://associados.amazon.com.br/help/node/topic/G227UW3NK58649S4)
- [Amazon: políticas, preços e disponibilidade](https://associados.amazon.com.br/help/operating/policies/)
- [Mercado Livre: canais de divulgação](https://www.mercadolivre.com.br/l/afiliados-compartilhamento-de-publicacao)
- [Apple: Performance Partners](https://performance-partners.apple.com/program-overview)
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [TMDB: uso comercial](https://developer.themoviedb.org/docs/faq)

---

## Entrega atual — Biblioteca pessoal (02/10/2026)

Desejos, favoritos e listas privadas agora persistem na API. Biblioteca substitui
Clubes na barra e módulos demonstrativos foram ocultados nos fluxos reais.
[Contrato e limites](../backend/api/docs/library.md).

Próxima validação sugerida: homologação manual com duas contas/dispositivos, incluindo
logout, recuperação de rede e mudança concorrente de listas. Depois escolher um único
módulo social para tornar real. Compartilhar listas, mídia e chat continuam pendentes.
Push permanece preparado/desligado até Apple Developer/APNs.

## Direção anterior — comunidade (02/10/2026)

Estado detalhado após os itens 2 e 3: [inventário de demonstrações](DEMONSTRATION_INVENTORY.md) e [contrato/ativação de push](../backend/api/docs/community-notifications.md).

Pessoas, busca, sugestões e seguir/deixar de seguir já usam a API real. Em 02/10,
o feed de reviews também passou a usar a API, com opt-in de diário público,
paginação, denúncias e bloqueios. Comentários e reações foram conectados em 02/10, com permissões no servidor e
CLI administrativa auditada para denúncias. Veja [a retomada](SESSION_HANDOFF.md). Os componentes e a identidade visual atuais devem ser
preservados; as propostas históricas de reorganização abaixo não estão aprovadas.

Direção solicitada para depois: a comunidade produzir conteúdo no estilo de
fóruns, com posts ligados a universos/obras, conversas, humor e reações. Evoluir
por etapas, sem misturar responsabilidades com catálogo ou integrações externas.
Antes de abrir publicação e interação: denúncia, bloqueio, limites contra spam,
regras de spoilers/conteúdo adulto e resposta clara ao autor. IA pode ajudar na
triagem, com revisão e possibilidade de contestação; não representa garantia de
moderação correta. Reposts e ranking continuam fora do escopo.
Posts de texto ligados a universos/obras e central de atividade foram implementados em 02/10. Push está preparado e desligado até Apple Developer/APNs. Reposts e triagem por IA ainda não foram implementados. Denúncias, bloqueios e limites iniciais já têm persistência;
as denúncias aguardam revisão manual, sem prazo automático prometido.

As seções seguintes registram propostas antigas e precisam ser reavaliadas frente
ao estado atual: autenticação, diário, tratamentos de erro e App Icon já tiveram
implementações posteriores.

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
