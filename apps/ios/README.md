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

### Fonte Archivo

O projeto foi montado sem acesso à internet, então a fonte variável **Archivo** (Google
Fonts) não está incluída. O app cai pro system font automaticamente se ela não for
encontrada, então funciona sem esse passo — mas pra ficar pixel-perfeito, siga
`Multiverse/Resources/Fonts/README.md`.

### Variáveis de ambiente

O conteúdo ainda vem dos JSONs locais através de `MockRepository`. A autenticação Google
e o Analytics usam o `GoogleService-Info.plist` do projeto Firebase cadastrado para
`com.nexussoft.multiverse`; não há backend próprio nesta etapa.

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

**Regra de dependência:** Views só falam com `AppStore`/`AuthStore` (via `@Environment`);
`AppStore`/`AuthStore` só falam com os protocolos `MultiverseRepository`/`AuthRepository`;
só `MockRepository`/`MockAuthRepository` conhecem `sample-data.json` e `UserDefaults`. Pra
trocar por um backend de verdade (Supabase/Firebase — ver seção abaixo), basta implementar
os dois protocolos de novo e passar a instância no `init` de `AppStore`/`AuthStore`; nenhuma
tela muda.

### Autenticação

O botão Google usa `FirebaseAuthRepository`, Google Sign-In e Firebase Authentication.
`GoogleService-Info.plist` é incluído somente no app pelo XcodeGen; o esquema de retorno
OAuth fica em `Multiverse/Resources/Info.plist`. Os SDKs são resolvidos pelo Swift Package
Manager. A sessão usa o UID do Firebase e é restaurada pelo SDK; tokens não são gravados
manualmente em `UserDefaults`.

Apple conserva o visual e permanece indisponível. Cadastro e login por e-mail usam
Firebase Auth; a confirmação de seis dígitos está conectada às funções preparadas em
`../../backend/firebase/`, que ainda precisam ser configuradas e publicadas. A recuperação usa link
do Firebase para a tela Nova senha, com Associated Domains preparado. Veja
[guia de ativação do Firebase](../../backend/firebase/README.md) para as dependências de ativação. `MockAuthRepository` permanece disponível para desenvolvimento.
O catálogo e as interações continuam usando `MockRepository`: esta etapa não implementa
persistência remota de perfis, nomes de usuário, diário ou feed. O perfil usa o UID do Firebase e o nome de exibição. O apelido de cadastro é local e
não representa reserva de um @usuário global. O onboarding e os ajustes locais são
separados por UID; sair descarta o estado de conteúdo em memória.

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

### Fase 2 — backend real

Ver `../../design/design_handoff_multiverse/README.md` (seção "Para o backend"). O plano é Supabase ou
Firebase, com tabelas equivalentes aos modelos em `Core/Models.swift`, mais `follows`,
`votes` (alvo polimórfico — já modelado assim em `PollTopic`) e `likes`.

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
