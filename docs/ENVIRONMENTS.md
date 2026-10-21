# Homologação, produção e desenvolvimento local

Atualizado em 21/10/2026. Este guia é a fonte operacional do lote L06. A arquitetura
continua Feature-First/Core no iOS e Controller/Service/Config no NestJS.

## Regra de custos definida por Lucas

Em 21/10/2026, Lucas pediu para **sempre limitar qualquer gasto** e escolheu
**manter a homologação sem faturamento por enquanto**. Não vincular conta de
faturamento, ativar Blaze, contratar planos ou provisionar novos recursos pagos
sem um teto de gasto aprovado para o serviço e período. Não presumir que a
autorização para publicar inclui autorização financeira.

Preferir planos gratuitos e limites que interrompam o consumo. Quando o provedor
não oferecer bloqueio efetivo para o serviço, explicar essa limitação antes de
qualquer ativação paga; alertas, quotas e limites de instâncias não equivalem a um
teto financeiro garantido. O alerta mensal de R$ 50 registrado anteriormente em
produção não comprova um limite rígido. Os serviços existentes de produção não
foram alterados nesta etapa.

Lucas autorizou a chave Resend **Multiverse HML**, somente envio pelo domínio
`somosmultiverse.com.br`, com armazenamento exclusivo no Secret Manager de staging.
A criação permanece pendente: o armazenamento depende de faturamento, conforme os
[pré-requisitos do Secret Manager](https://googleapis.dev/nodejs/secretmanager/latest/index.html#before-you-begin).
O formulário foi cancelado sem gerar a chave. Não copiar o segredo de produção
nem substituir o destino aprovado por outro cofre sem autorização.

## Matriz de ambientes

| Configuração | Homologação | Produção |
| --- | --- | --- |
| iOS | Debug / `Configuration/Staging.xcconfig` | Release / `Configuration/Production.xcconfig` |
| Nome instalado | Multiverse HML | Multiverse |
| Bundle do app | `com.nexussoft.multiverse.staging` | `com.nexussoft.multiverse` |
| Widget | Bundle do app + `.widgets` | Bundle do app + `.widgets` |
| App Group | `group.com.nexussoft.multiverse.staging` | `group.com.nexussoft.multiverse` |
| Links internos | `multiverse-staging://` | `multiverse://` |
| Firebase | `multiverse-staging-7f87c` | `multiverse-7f87c` |
| Firebase alias | `staging` (também é o default seguro) | `production` |
| API `APP_ENV` | `staging` | `production` |
| API `NODE_ENV` | `production` | `production` |
| API hospedada | **Pendente: Railway indisponível** | `https://api-production-6e8d.up.railway.app/api/v1` |
| Banco hospedado | **Pendente: PostgreSQL próprio em staging** | Serviço Postgres existente em production |

`APP_ENV` identifica dados e implantação; `NODE_ENV` identifica o modo do Node.
Não usar `NODE_ENV=staging`. O CI usa `APP_ENV=test`, Firebase fictício e PostgreSQL
descartável; os testes nunca carregam o `.env` do desenvolvedor.

## O que já foi separado

- Firebase Staging criado sem copiar usuários, dados ou credenciais de produção.
  App iOS `1:663870288715:ios:79160fa0300d1358602ece` registrado; Google e
  e-mail/senha ativados. Nome OAuth **Multiverse Homologação**, suporte
  **lucasamorim78c@gmail.com**. Plano Spark; nenhum faturamento foi vinculado.
- Configurações públicas do Firebase próprias por build. A etapa de build valida
  projeto, bundle, callbacks e URL e copia só o plist selecionado. Configuração
  cruzada interrompe o build; a inicialização do app também valida a identidade.
- Apps podem coexistir pelo bundle diferente. Sessão Firebase/Keychain,
  preferências e links ficam separados. O widget deriva seu grupo do ambiente.
  Debug continua sem App Groups/Associated Domains por usar Personal Team;
  compartilhamento real com widget e links universais exigem assinatura adequada.
- Clientes HTTP enviam `X-Multiverse-Environment`. A API rejeita divergência com
  HTTP 409 / `ENVIRONMENT_MISMATCH` antes de autenticar ou escrever. O header não
  é autenticação: JWT continua validado pelo Admin SDK contra o projeto correto.
  Clientes antigos sem header continuam compatíveis; novos clientes também
  rejeitam resposta que declare outro ambiente.
- `GET /api/v1/health` inclui `environment`, além de `status` e `service`.
  `GET /api/v1/health/ready` acrescentado no lote local L10 confere acesso pelo pool
  e identidade do banco, com resposta 200/503 e cache de até 5 segundos.
  Isso não configura um monitor contínuo nem valida provedores externos.
- API valida combinações de APP_ENV, projeto Firebase, JSON Admin e ambiente
  Railway. Emulador só é permitido no ambiente local com projeto `demo-`.
- Migration 029 registra identidade de ambiente/Firebase no banco. O migrador
  exige destino explícito, confere a identidade **antes de aplicar migrations**,
  vincula um banco vazio em transação e permite rerun após falha. O servidor
  recusa inicialização se o banco não estiver identificado corretamente.
- Firebase Hosting prepara a associação do app a partir do projeto do deploy;
  o arquivo gerado fica em `.firebase/hosting`, ignorado pelo Git. Homologação já
  publicada em `https://multiverse-staging-7f87c.web.app`, com associação conferida
  via HTTP 200 para o bundle staging. Isso não hospeda a API NestJS nem as Functions.

## Usar o app agora

Debug seleciona homologação automaticamente. `MULTIVERSE_API_BASE_URL` de staging
está intencionalmente vazio: cadastro/onboarding e conteúdo dependentes da API
ficam indisponíveis até o serviço hospedado existir. Isso não é um mock funcional.
As telas locais, inclusive termos e ajuda, continuam disponíveis.

Quando o Railway fornecer o domínio, preencher `Staging.xcconfig` com a URL real
HTTPS terminada em `/api/v1`. Em xcconfig, escrever `https:/$()/dominio/api/v1`
para que `//` não seja interpretado como comentário. Executar `make ios-generate`.
O build falha se Debug usar o host de produção. Release só aceita o host de
produção configurado; troca futura de domínio exige atualizar a política em
`AppEnvironment.swift` e `configure_environment.py` junto da configuração.

Para testar uma API de staging executada no Mac, é possível passar
`MULTIVERSE_API_BASE_URL=http://127.0.0.1:3000/api/v1` no build/scheme Debug.
Essa API precisa usar `APP_ENV=staging`, Firebase de staging e um banco exclusivo.
Não apontar o app staging para a API local com Firebase demo: os projetos são
intencionalmente diferentes. Testes iOS usam URL loopback na porta 1 e transportes
injetados; não precisam da API nem de uma conta real.

## Desenvolvimento da API com emulador

O `.env.example` usa `APP_ENV=local`, `demo-multiverse-local`, Auth emulator
`127.0.0.1:9099` e banco `multiverse_local` em `127.0.0.1:55432`.
O Compose usa o projeto `multiverse-local`, com volume separado do antigo Compose.
Não importar dump de produção nem reaproveitar o volume antigo para homologação.

```sh
# Terminal 1, a partir da raiz
cd backend/firebase
firebase emulators:start --only auth --project demo-multiverse-local

# Terminal 2, a partir da raiz
cd backend/api
cp -n .env.example .env  # não sobrescrever segredos locais
# Ajustar POSTGRES_PASSWORD e a mesma senha em DATABASE_URL.
docker compose up -d --wait
npm run db:migrate
npm run start:dev
```

Para projeto demo/emulador não configurar credenciais de produção. Em um ambiente
real, usar ADC da identidade daquele projeto ou uma conta de serviço exclusiva,
com acesso mínimo necessário ao Firebase Authentication. Segredos ficam no
provedor; nunca no app, plist público, Git ou exemplos.

## Retomar provisionamento no Railway

A criação de `staging` falhou com **Deploys have been paused temporarily**. A
consulta posterior retornou só `production`; nenhum ambiente parcial foi criado.
O [status oficial](https://status.railway.com/) em 21/10 informava builds pausados
e funcionalidades da API indisponíveis. Não existe URL de staging para configurar.

Após a recuperação do provedor, conferir custos e limites antes de criar API e
Postgres: a decisão de manter a homologação sem faturamento não autoriza novos
gastos no Railway. Com o orçamento e os controles aprovados:

1. Criar ambiente **vazio** `staging` no projeto `multiverse`
   (`3d9b8511-b917-4a7a-8a7d-577853c8a011`). Não duplicar variáveis/volumes de production.
2. Criar Postgres exclusivo e serviço `api`. Configurar valores de
   `backend/api/configuration/staging.env.example`, referência ao **Postgres de staging**
   e credencial Firebase Admin **de staging**. A chave privada ainda não foi criada.
3. Configurar predeploy `npm run db:migrate` e readiness `/api/v1/health/ready`.
   Publicar o código local revisado pelo CLI com destino explícito staging; não
   fazer push em master para testar, pois master tem autodeploy de produção.
4. Verificar `environment=staging`, banco identificado, 401 sem token e recusa
   de token de produção. Preencher URL real no iOS e repetir testes.
5. Homologar duas contas novas: cadastro, Google, diário/biblioteca, exclusão,
   logout/troca de conta e links. Não usar usuários reais de produção como fixtures.

Usar `--environment staging --service api` em toda operação Railway. O vínculo
CLI usado para a tentativa ficou em `/tmp/multiverse-staging-ops`, sem alterar o
vínculo do repositório com produção. Não copiar JSONs Admin existentes no iOS.

## Pendências Firebase de homologação

Google/e-mail ativados não significam que o cadastro completo está homologado.
O app verifica e-mail por código usando Functions + Firestore + Resend + App Check.
Esses componentes ainda precisam ser provisionados no **projeto staging**:

- Deploy de Functions adiado pela decisão de Lucas de manter Spark, sem
  faturamento. O [plano Blaze é necessário para publicar Cloud Functions](https://firebase.google.com/docs/functions/get-started).
  Não ativar enquanto essa decisão permanecer vigente.
- Criar Firestore, publicar regras fechadas, configurar TTL em `purgeAt`, segredos
  exclusivos `VERIFICATION_CODE_SECRET` e `RESEND_API_KEY`, e remetente identificável
  como homologação. Não copiar o segredo de produção.
- Remetente local preparado como `Multiverse HML <elesys@somosmultiverse.com.br>`
  no arquivo ignorado `functions/.env.multiverse-staging-7f87c`. Os 14 testes de
  Functions passaram novamente; isso não comprova envio real em staging.
- Registrar App Check do app staging e tokens de debug dos dispositivos de teste.
- Publicar `functions:multiverse-auth,firestore:rules` com
  `--project multiverse-staging-7f87c` explícito; validar envio/confirmar código,
  recuperação de senha e abertura do link. Nenhum e-mail foi enviado nesta etapa.
- Apple, APNs, App Attest Release, App Groups e teste físico continuam dependentes
  do Apple Developer e das configurações futuras; não foram habilitados neste lote.

## Antes de uma futura publicação em produção

Não houve deploy da API/migrations de produção neste lote. Antes de publicar:

1. Configurar `APP_ENV=production` no serviço API de produção. O novo migrador
   exige essa variável; runtime mantém compatibilidade com NODE_ENV=production.
2. Revisar backup e destino. A adoção de banco legado sem identidade só é permitida
   com APP_ENV/project de produção explícitos; um banco já identificado não pode
   ser renomeado pelo migrador. Não apagar a linha para contornar uma recusa.
3. Executar migrations 028/029 e API antes do novo app. Migrations anteriores
   conservam checksums. Rollback do código não remove dados/identidade do banco.
4. Gerar Release, revisar assinatura e realizar as validações de lançamento.

A validação integrada da homologação ficou **adiada por decisão de Lucas** em
21/10/2026. A retomada acima é um roteiro futuro, não uma autorização para ativar
faturamento ou iniciar provisionamento pago. O lote local L10 adicionou
[readiness e diagnóstico privado](../backend/api/docs/operations.md) sem deploy.

## Verificação

`make environment-check` valida configurações reais e cenários cruzados sem
Xcode. CI executa esse gate junto das traduções. `make api-check` cobre migrador
real com PostgreSQL, rejeição antes de escrita, bootstrap e Admin SDK com audience
de outro projeto. `make ios-test` cobre recursos empacotados, URLs, links e headers.
Esses testes não substituem login real, entrega de e-mail nem QA em dois aparelhos.

Validação de 21/10/2026: Debug com 296 testes/35 suítes; Release compilado sem
assinatura; recursos de ambos os pacotes conferidos. API: 110 unitários e 160 HTTP/
PostgreSQL, incluindo falha de migration + retry. Firebase: 14 testes; smoke Auth
emulator com adaptador real aprovado. Configuração: 3 testes; traduções: 1.244;
workflow aprovado pelo actionlint. CI remoto e integração cloud continuam pendentes.
