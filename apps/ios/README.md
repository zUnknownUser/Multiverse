> Estado consolidado e pendências: [resumo de retomada](../../docs/SESSION_HANDOFF.md).

# Multiverse — iOS

Rede social pra fãs de universos fictícios (Marvel, DC, Warcraft) — diário + reviews + rede.
App iOS nativo em SwiftUI, construído no Windows/VS Code e preparado pra abrir direto no
Xcode via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

Os comandos abaixo são executados em `apps/ios/`. Na raiz do monorepo, use
`make ios-generate`, `make ios-open` e `make ios-test`.

## Requisitos

- macOS com Xcode 16 ou mais recente
- iOS 17.0+ (deployment target)
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup no Mac

```bash
git clone <repository>
cd Multiverse/apps/ios

brew install xcodegen
xcodegen generate

open Multiverse.xcodeproj
```

No Xcode:

1. Selecione o target **Multiverse** → aba **Signing & Capabilities**.
2. Marque **Automatically manage signing** e escolha seu **Development Team**.
3. Rode no Simulator (⌘R) ou num dispositivo físico.

O `project.yml` usa assinatura automática com a equipe `5RS2AA677K`, a mesma do Verbum.
Os targets do app e dos widgets compartilham o App Group `group.com.nexussoft.multiverse`.
Para gerar os perfis de desenvolvimento, conecte e desbloqueie um iPhone registrado nessa
equipe e execute pelo Xcode. Certificados e provisioning profiles não ficam no repositório.

Os dados compartilhados com widgets são vinculados à sessão ativa. Logout e troca de
conta limpam o snapshot e solicitam atualização ao WidgetKit; respostas atrasadas da
sessão anterior são descartadas. O iOS controla quando a atualização aparece na tela.

### Fonte Archivo

A fonte variável **Archivo** já está incluída no app e nos widgets, com a licença
OFL original. O XcodeGen vincula os arquivos e os dois plists registram a fonte.
Não é necessário baixá-la manualmente. Origem e detalhes em
`Multiverse/Resources/Fonts/README.md`.

### Variáveis de ambiente

Catálogo, perfil, onboarding, diário, pessoas e feed usam a API NestJS conforme a
seção "Conectar à API" abaixo. Comentários e reações também usam persistência real;
clubes, mensagens, salas e outros módulos ainda contêm dados de demonstração.
Autenticação e Analytics
usam o `GoogleService-Info.plist` cadastrado para `com.nexussoft.multiverse`.

## Arquitetura

Feature-First + Core + DesignSystem:

```
Multiverse/
├── App/            — shell do app: entry point, RootView, tab bar, sheets globais
├── Core/           — infraestrutura e código transversal (nunca UI de feature)
│   ├── AppStore.swift        — @Observable central, único estado de conteúdo do app
│   ├── Models.swift          — modelos de domínio (espelham sample-data.json)
│   ├── Navigation.swift      — Route / AppTab
│   ├── Logic.swift           — fórmulas puras (determinísticas, iguais ao protótipo)
│   ├── StaticContent.swift   — conteúdo estático que não está no JSON
│   ├── Repository/           — MultiverseRepository (protocolo) + MockRepository
│   └── Auth/                 — AuthRepository (protocolo) + MockAuthRepository + modelos
├── DesignSystem/   — tokens visuais (Theme) + componentes de UI reutilizáveis entre features
└── Features/       — uma pasta por fluxo: Views + componentes específicos daquele fluxo
    ├── Onboarding/, Auth/, Home/, Search/, Notifications/, Profile/, Universe/,
    │   Item/, Thread/, ReadingOrder/, ListDetail/, Diary/, Wrapped/, LogSheet/, Settings/
```

**Regra de dependência:** Views acessam `AppStore`/`AuthStore` via `@Environment`.
Os stores usam protocolos injetáveis: `MultiverseRepository` para conteúdo,
`AuthRepository` para autenticação e `AccountAPI` para perfil/onboarding remoto.
`MockRepository` mantém os módulos ainda não migrados e os previews/testes.
`CatalogAPIClient` e `AccountAPIClient` conectam os fluxos reais; o layout é preservado.

### Autenticação

O botão Google usa `FirebaseAuthRepository`, Google Sign-In e Firebase Authentication.
`GoogleService-Info.plist` é incluído somente no app pelo XcodeGen; o esquema de retorno
OAuth fica em `Multiverse/Resources/Info.plist`. Os SDKs são resolvidos pelo Swift Package
Manager. A sessão usa o UID do Firebase e é restaurada pelo SDK; tokens não são gravados
manualmente em `UserDefaults`.

Apple conserva o visual e permanece indisponível. Cadastro e login por e-mail usam
Firebase Auth; a confirmação de seis dígitos está conectada às funções preparadas em
`../../backend/firebase/`, publicadas em 01/10/2026. O recebimento e o fluxo
integrado ainda exigem teste manual. A recuperação usa link
do Firebase para a tela Nova senha, com Associated Domains preparado. Veja
[guia de ativação do Firebase](../../backend/firebase/README.md) para as dependências de ativação. `MockAuthRepository` permanece disponível para desenvolvimento.
Perfil, @usuário e onboarding agora usam a API NestJS com PostgreSQL. A sessão
Firebase é complementada pelo perfil remoto; uma conta Google nova passa pelas
mesmas telas de nome/usuário/avatar já existentes. A disponibilidade do @usuário é
consultada na API e a reserva é garantida no banco no momento de salvar.
O app restaura o onboarding por UID, salva seleções com debounce e aguarda o servidor
antes de avançar/concluir. Uma falha permite tentar novamente ou sair, sem entrar
com um perfil fictício. O mínimo de pessoas a seguir acompanha a comunidade real;
sem sugestões, essa etapa é pulada. Conflitos entre aparelhos exigem recarregar.

O catálogo, feed, diário, pessoas, comentários e reações usam a API.
Veja [contratos de interação e moderação](../../backend/api/docs/interactions.md).
Registros novos do diário guardam o instante de publicação (`loggedAt`). A apresentação
agrupa por mês e ano no calendário/fuso do usuário e formata as datas em PT-BR ou EN.
A frequência Pro usa os últimos 105 dias do diário; as horas anuais consideram o ano
atual. As amostras e o Wrapped do protótipo continuam no recorte de setembro de 2026.
O diário da sessão real é persistido pela API. Módulos de demonstração mantêm
suas limitações de persistência; não representam uma comunidade em produção.
Ajustes continuam locais por UID. Exclusão de conta agora passa pela API para
remover tanto a identidade Firebase quanto o perfil e progresso no PostgreSQL.

### Conectar à API

Siga o [guia da API](../../backend/api/README.md) para iniciar PostgreSQL, aplicar
migrations, configurar Firebase Admin e executar NestJS.

- Debug e Release usam `https://api-production-6e8d.up.railway.app/api/v1`.
- Para desenvolvimento local no simulador, sobrescreva o endereço com
  `http://localhost:3000/api/v1` no scheme Debug. A permissão ATS é restrita
  a rede local; não há liberação geral de HTTP.
- `MULTIVERSE_API_BASE_URL` em `project.yml` controla o endereço incluído no plist.
  Em Debug também pode ser sobrescrito pela variável de ambiente do scheme.
- Release exige endereço HTTPS. Após alterar `project.yml`, regenere com XcodeGen.
- Tokens Firebase são obtidos do SDK a cada chamada e renovados uma vez em caso
  de 401. Não são salvos pelo cliente HTTP nem incluídos nos logs.

Sem API/credenciais configuradas, o app compila, mas o fluxo real de conta exibe
um erro de conexão. O plist Firebase do app não é uma credencial Admin do servidor.

### Estado Pro

`ProStore` coordena a interface, enquanto `ProEntitlementClient` consulta e observa
os direitos de compra. A implementação StoreKit aceita apenas transações verificadas
dos produtos Pro; usa [`currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
para preservar o período de tolerância de cobrança indicado pela Apple.
O acesso é atualizado nas transações e quando o app volta ao primeiro plano.
Restauração informa falhas, trata cancelamento e bloqueia operações duplicadas;
respostas de consultas antigas não sobrescrevem o resultado mais recente.
O paywall recarrega os produtos ao abrir. O botão só anuncia gratuidade quando o
produto contém uma oferta gratuita e o StoreKit confirma a elegibilidade da conta;
a duração vem da oferta. Sem essa confirmação, mostra "Assinar Pro". O selo de economia
compara um ano com 12 mensalidades da mesma moeda, arredondando para baixo. Preços
iguais, planos de períodos diferentes ou moedas diferentes não recebem selo.

Os testes usam um cliente injetado e não realizam compras. O StoreKit local continua
configurado no scheme para testes manuais. Atualmente o direito pertence à conta da
App Store; a vinculação a uma conta Multiverse e a validação no backend ainda não
estão implementadas.

### Analytics

Firebase Analytics inicializa com o app. Os eventos `login` e `sign_up` usam
`method: google` ou `method: password`; `sign_up` só é emitido quando Firebase confirma
a criação de uma conta.
`logout` é emitido após sair com sucesso. Restaurar a sessão não conta como novo login.
Os eventos não incluem nome, e-mail, tokens ou um User ID personalizado.

A coleta é habilitada explicitamente no app. No console Firebase, confirme a integração
com Google Analytics em **Configurações do projeto → Integrações** (o plist fornecido
originalmente contém `IS_ANALYTICS_ENABLED = false`). Para inspecionar eventos em
DebugView, adicione `-FIRDebugEnabled` aos argumentos de execução do scheme no Xcode.

Validação manual: entrar com Google, cancelar a tela de autorização, reabrir o app,
sair, entrar com outra conta e conferir o usuário em Firebase Authentication. O login
real exige a autorização do titular da conta; os testes automatizados usam um cliente
injetado e não autenticam uma conta Google real.

### Próximas etapas do backend

A stack definida é NestJS + PostgreSQL, com Firebase para autenticação e Analytics.
Conta, catálogo, diário, pessoas e interações em reviews estão integrados. A
migração dos demais módulos acontece por fluxo, preservando IDs e modelos existentes. Veja o [guia da API](../../backend/api/README.md).

## Testes

```bash
xcodebuild test -scheme Multiverse -destination "platform=iOS Simulator,name=iPhone 16"
```

`MultiverseTests/` cobre as regras de negócio determinísticas (`Logic`) e o comportamento
do `AppStore` (precedência de "visto" entre diário/checks, persistência de voto/follow
através do repositório).

## Design de referência

`../../design/design_handoff_multiverse/` tem a especificação completa (README, protótipo HTML,
screenshots de cada tela, dados de amostra) usada como fonte de verdade visual. `../../design/Login Multiverse/` tem as capturas do fluxo de autenticação. Nenhum dos dois é necessário pra
compilar o app — são só material de referência.

## Backlog

[backlog](../../docs/BACKLOG.md) documenta melhorias de produto/arquitetura identificadas mas conscientemente
adiadas (aba Arena, identidade visual, estados de erro/offline, missões da primeira semana,
notas de adaptação pro iPhone Duo, plano de migração pra SwiftData) — com o motivo de cada
adiamento.

## Estado deste ambiente

Projeto gerado por XcodeGen e validado no Xcode com build para simulador e testes
automatizados, incluindo autenticação com cliente injetado. A autorização
Google com uma conta real e o recebimento de eventos no console devem ser conferidos
no ambiente Firebase configurado.

## Localização (PT-BR e EN)

O app e os widgets compartilham `Multiverse/Resources/Localizable.xcstrings`.
`L10n` lê `Locale.preferredLanguages` na ordem de preferência: variantes `en-*`
usam inglês; variantes `pt-*` usam português brasileiro. Se não houver idioma
compatível, o fallback é PT-BR. A preferência por aplicativo nos Ajustes do iOS
é respeitada; não há seletor adicional dentro do app.

Para testar no Xcode, edite **Scheme → Run → Options → App Language → English**.
No aparelho, escolha inglês nos ajustes de idioma do Multiverse. O iOS reinicia
o app ao trocar seu idioma.

- Use `L10n.text` para rótulos e `L10n.format` com placeholders posicionais para
  frases com valores. Adicione ambas as traduções ao catálogo; as entradas são
  mantidas manualmente, inclusive as variantes plurais. A extração automática do
  Xcode está desativada em `project.yml` para evitar entradas incompletas.
- Não traduza IDs, valores de enums persistidos, chaves de API ou texto escrito
  pelas pessoas. Localize valores de domínio somente na apresentação.
- Os JSONs de demonstração em `Resources/en.lproj/` têm conteúdo inglês e mantêm
  os mesmos IDs, relações e códigos dos JSONs originais em português.
- O idioma dos e-mails gerenciados pelo Firebase Auth acompanha o app. O template PT-BR/EN
  do serviço externo de códigos acompanha o locale enviado pelo app.
- As traduções StoreKit são locais ao arquivo de testes; publicar metadados
  comerciais traduzidos no App Store Connect é uma etapa separada.

Validação do catálogo sem compilar:

```sh
python3 apps/ios/scripts/check_localization.py
```

Testes nos dois idiomas, a partir de `apps/ios/`:

```sh
xcodebuild -project Multiverse.xcodeproj -scheme Multiverse -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath DerivedData -testLanguage en -testRegion US test
xcodebuild -project Multiverse.xcodeproj -scheme Multiverse -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath DerivedData -testLanguage pt-BR -testRegion BR test
```
