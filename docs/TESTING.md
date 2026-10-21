# Testes e integração contínua

## Preparação local

- Python 3 para o catálogo de tradução.
- API: Node 24 (`backend/api/.nvmrc`) e `npm ci` em `backend/api`.
- Firebase Functions: Node 22 e `npm ci` em `backend/firebase/functions`.
- Docker em execução para o PostgreSQL descartável.
- iOS: macOS, Xcode com simulador iPhone 17 Pro e XcodeGen (`brew install xcodegen`).

Os comandos abaixo partem da raiz do repositório. Use a versão Node indicada ao
instalar/testar cada backend; a API também aceita Node 26 conforme `engines`.
O CI executa cada backend em um job com sua própria versão de Node.

```sh
make localization-check
make api-check
make backend-test
make ios-test
```

`make test` reúne tradução, iOS, Firebase e a verificação completa da API, usando
o Node disponível no terminal. Para reproduzir exatamente as versões de runtime
do CI, execute os comandos separados com Node 24 para a API e 22 para Firebase.
`make api-test` executa somente unitários/HTTP, com o mesmo banco descartável.

## PostgreSQL dos testes

`make api-check` / `npm run check:local` e `make api-test` / `npm run test:local`
criam um container `postgres:18-alpine` exclusivo, com porta aleatória publicada
apenas em `127.0.0.1`. Esperam a prontidão, definem `TEST_DATABASE_URL`, executam a
suíte e removem container/volume ao terminar, inclusive quando um teste falha ou
a execução recebe SIGINT/SIGTERM. Não reutilizam `DATABASE_URL`, `.env`, o Compose
de desenvolvimento ou uma `TEST_DATABASE_URL` herdada.

Sem Docker, forneça explicitamente um PostgreSQL exclusivo para testes, com
permissão para criar schemas:

```sh
cd backend/api
export TEST_DATABASE_URL='postgresql://usuario:senha@127.0.0.1:5432/multiverse_test'
npm run check
# Ou apenas:
npm test
npm run test:e2e
```

`npm test` contém os unitários. `test:e2e`, `test:all` e `check` exigem banco e
retornam erro se a URL estiver ausente, inválida ou inacessível. As suítes HTTP
executam em série, com até 60 segundos para os hooks de preparação/limpeza. Cada
suíte cria um schema aleatório, aplica todas as migrations e remove seu próprio
schema ao terminar. Não aponte `TEST_DATABASE_URL` para produção.

O setup dos testes força `NODE_ENV=test`, ignora `.env`, remove a URL de aplicação
e as credenciais de provedores herdadas e desliga push/voz. Os HTTP usam banco
real, mas identidades Firebase e serviços externos controlados; não homologam
APNs, e-mail, login Google/Apple, App Attest ou voz em aparelhos físicos.

Se Docker for encerrado ou o processo receber SIGKILL, o shell pode não executar
a limpeza. Os containers deste comando têm o prefixo `multiverse-test-` e a label
`com.multiverse.test-database=true`; inspecione e remova somente o container da
execução interrompida. Nenhum volume persistente nomeado é criado.

## iOS

`make ios-test` gera o projeto e roda as suítes em série. O build de teste aponta
a API para localhost sem serviço, evitando utilizar a API de produção. Isso não
substitui um ambiente de homologação do aplicativo (L06 do plano).

Para outro simulador ou um runner sem assinatura:

```sh
make ios-test \
  IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  IOS_TEST_OPTIONS='-parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO MULTIVERSE_API_BASE_URL=http://127.0.0.1:1/api/v1'
```

## GitHub Actions

[CI](../.github/workflows/ci.yml) executa em pull requests, pushes em `master` e
disparo manual. São quatro checks independentes:

| Check | Ambiente | Verificação |
| --- | --- | --- |
| Translations (PT-BR / EN) | Ubuntu 24.04, Python 3.12 | Catálogo, placeholders e referências |
| API (PostgreSQL 18) | Ubuntu 24.04, Node 24, PostgreSQL 18 | `npm ci` + formatação, lint, tipos, build, unitários e HTTP |
| Firebase Functions | Ubuntu 24.04, Node 22 | `npm ci` + build e testes |
| iOS Simulator | macOS 26, Xcode 26.6, iOS 26.5 | XcodeGen + build e testes sem certificado de distribuição |

Actions fixadas por SHA, permissões somente de leitura, sem segredos de produção.
O PostgreSQL é um serviço descartável do job. Falha em qualquer comando deixa o
respectivo check vermelho. Uma nova execução cancela a anterior da mesma ref.
Dependências npm seguem os lockfiles; as versões diretas de Swift Packages são
fixadas no `project.yml`. Imagens de runner/PostgreSQL e XcodeGen ainda podem
receber atualizações; este fluxo é repetível, mas não um build bit a bit idêntico.

A configuração local não executa o workflow no GitHub. A primeira execução remota
deve ser conferida depois do push. Tornar os checks obrigatórios em regras de
branch e condicionar o autodeploy Railway à aprovação são configurações remotas
separadas; este lote não altera o deploy existente.

Versões do runner conferidas na
[lista oficial de macOS 26](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).
Quando Xcode/simuladores forem removidos da imagem, atualizar ambos no workflow.

## Isolamento de ambientes (L06)

`make environment-check` valida o pareamento dos xcconfigs, plists Firebase,
callbacks e URL da API. O CI executa esse gate sem precisar de segredos/Xcode.
Debug usa o app e Firebase de staging, com API loopback em testes. O build Release
valida os recursos de produção sem executar autenticação.

A suíte API verifica o migrador real em PostgreSQL vazio, reruns, recusa de banco
legado para staging e recusa de identidade cruzada no startup. O Admin SDK real
rejeita `aud` de produção em uma configuração staging antes de consultar chaves;
o teste não usa um token ou conta real.

Smoke opcional com Firebase CLI instalado: `npm --prefix backend/api run build`;
em `backend/firebase`, executar
`firebase emulators:exec --only auth --project demo-multiverse-local 'node ../api/scripts/check-auth-emulator.mjs'`.
Cria/verifica/exclui somente uma conta do emulador, sem envio de e-mail ou credenciais
reais. Ver [pendências de homologação integrada](ENVIRONMENTS.md).

## Readiness e diagnóstico operacional (L10)

Os mesmos `make api-check` / `make api-test` incluem cache/concorrência/prazo do
probe e os testes HTTP/PostgreSQL de `/health/ready`. A suíte bloqueia uma tabela
do banco descartável para conferir 503 dentro do prazo, liveness ainda disponível
e recuperação após liberar o bloqueio; também rejeita identidade divergente.

O relatório operacional é testado com filas vazias e pendências artificiais,
ignorando trabalhos concluídos, sem expor identidades nem alterar os registros.
Também verifica transação somente leitura/repeatable read e recusa de ambiente
incorreto antes de consultar as filas. Nenhum desses testes chama provedores
externos, envia e-mail/push ou usa contas reais.
