# Multiverse

Rede social pra fãs de universos fictícios (Marvel, DC, Warcraft) — diário + reviews + rede.
App iOS nativo em SwiftUI, construído no Windows/VS Code e preparado pra abrir direto no
Xcode via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Requisitos

- macOS com Xcode 16 ou mais recente
- iOS 17.0+ (deployment target)
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup no Mac

```bash
git clone <repository>
cd Multiverse

brew install xcodegen
xcodegen generate

open Multiverse.xcodeproj
```

No Xcode:

1. Selecione o target **Multiverse** → aba **Signing & Capabilities**.
2. Marque **Automatically manage signing** e escolha seu **Development Team**.
3. Rode no Simulator (⌘R) ou num dispositivo físico.

Não há `DEVELOPMENT_TEAM`, certificado ou provisioning profile no repositório — isso é
intencional (ver `project.yml`); a configuração de assinatura é feita localmente no Mac.

### Fonte Archivo

O projeto foi montado sem acesso à internet, então a fonte variável **Archivo** (Google
Fonts) não está incluída. O app cai pro system font automaticamente se ela não for
encontrada, então funciona sem esse passo — mas pra ficar pixel-perfeito, siga
`Multiverse/Resources/Fonts/README.md`.

### Variáveis de ambiente

Nenhuma. Todo o conteúdo hoje vem de `Resources/sample-data.json` através de
`MockRepository`/`MockAuthRepository` (ver arquitetura abaixo) — não há chaves de API pra
configurar nesta fase.

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

Fluxo completo (boas-vindas, criar conta com verificação por e-mail, entrar, esqueci a
senha, ajustes de conta, sair, excluir conta) rodando sobre `MockAuthRepository`, que
persiste a sessão em `UserDefaults` entre execuções. Conta de demonstração:

- **E-mail:** `duda.kaminski@gmail.com`
- **Usuário:** `@duda.lore`
- **Senha:** `Multiverse1`

### Fase 2 — backend real

Ver `design_handoff_multiverse/README.md` (seção "Para o backend"). O plano é Supabase ou
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

`design_handoff_multiverse/` tem a especificação completa (README, protótipo HTML,
screenshots de cada tela, dados de amostra) usada como fonte de verdade visual. `Login
Multiverse/` tem as capturas do fluxo de autenticação. Nenhum dos dois é necessário pra
compilar o app — são só material de referência.

## Backlog

`BACKLOG.md` documenta melhorias de produto/arquitetura identificadas mas conscientemente
adiadas (aba Arena, identidade visual, estados de erro/offline, missões da primeira semana,
notas de adaptação pro iPhone Duo, plano de migração pra SwiftData) — com o motivo de cada
adiamento.

## Estado deste ambiente

Este projeto foi desenvolvido no Windows, sem Xcode/SDK iOS disponível — ou seja, **nunca
foi compilado de verdade**. Passou por revisão estática extensiva (consistência de
assinaturas, símbolos, tipos), mas a validação final — build, execução no Simulator,
ajustes específicos de SDK — é o próximo passo no Mac.
