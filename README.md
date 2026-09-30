# Multiverse

App iOS e backend Firebase no mesmo repositório. Cada parte tem suas próprias
configurações, dependências e comandos de execução.

## Estrutura

```text
apps/ios/
├── project.yml              # Fonte de verdade do projeto Xcode
├── GoogleService-Info.plist  # Configuração cliente do Firebase
├── Configuration/           # StoreKit
├── Multiverse/              # App e recursos
├── MultiverseWidgets/       # Widgets e Live Activity
└── MultiverseTests/         # Testes iOS
backend/firebase/
├── firebase.json            # Configuração de publicação
├── functions/               # Funções TypeScript e testes
├── firestore.rules
└── hosting/                 # Associação de links com o app
docs/
└── BACKLOG.md
design/                      # Protótipos, screenshots e originais dos ícones
```

`apps/ios/Multiverse.xcodeproj` é gerado pelo XcodeGen e não é versionado.
Os ícones usados pelo app ficam no catálogo de assets em `apps/ios/Multiverse/Resources/`;
os arquivos de `design/` são referências e não entram na compilação.

## App iOS — Xcode

Requer macOS, Xcode com SDK iOS compatível com as dependências fixadas no `project.yml`
e XcodeGen (`brew install xcodegen`). O app tem deployment target iOS 17.0.

Na raiz do repositório:

```sh
make ios-open
```

Ou diretamente na pasta do app:

```sh
cd apps/ios
xcodegen generate
open Multiverse.xcodeproj
```

O caminho do projeto mudou: abra o `.xcodeproj` dentro de `apps/ios/`, inclusive se
houver um atalho antigo na lista de projetos recentes do Xcode.

Equipe, Bundle IDs, App Group, Firebase, StoreKit e dependências foram mantidos.
Detalhes de assinatura, arquitetura e autenticação: [guia iOS](apps/ios/README.md).

## Backend — VS Code ou outra IDE

Abra `backend/firebase/` na IDE de sua preferência, ou abra a raiz para ver o monorepo.
As funções usam Node.js 22 e npm. Na raiz:

```sh
make backend-install
make backend-test
```

Alternativa direta:

```sh
cd backend/firebase/functions
npm ci
npm test
```

O backend de confirmação por e-mail está preparado, mas não foi publicado.
Serviço de e-mail, segredos, App Check e links ainda precisam de configuração externa;
veja o [guia de ativação](backend/firebase/README.md).

Os comandos Firebase devem ser executados em `backend/firebase/`, onde estão
`firebase.json` e `.firebaserc`. Os comandos `make` acima não fazem deploy.

## Validação

Na raiz do monorepo:

```sh
make ios-build
make ios-test
make backend-test
```

Para escolher outro simulador instalado:

```sh
make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 16'
```

`make test` executa as duas suítes. Os testes automatizados não enviam códigos reais
nem substituem a validação de autenticação e links em um aparelho conectado ao Firebase.

## Documentação e referências

- [Arquitetura e configuração iOS](apps/ios/README.md)
- [Configuração e ativação do backend](backend/firebase/README.md)
- [Backlog](docs/BACKLOG.md)
- [Especificação de design](design/design_handoff_multiverse/README.md)

A reorganização preserva o código e o layout; não muda as regras de negócio nem publica
serviços externos. Dependências instaladas, artefatos de build e segredos locais seguem
fora do Git.
