# Preparação do Multiverse para lançamento

Registro consolidado em 21/10/2026 da auditoria solicitada por Lucas. O projeto
está em estágio de MVP avançado, com fluxos reais no app e no backend, mas ainda
tem lacunas funcionais, operacionais e de distribuição. A prioridade proposta é
completar e estabilizar a primeira versão antes de ampliar funcionalidades.

Lucas pediu que todos os achados fossem registrados para tratamento futuro.
O estado de cada item está indicado abaixo. Atualizar cada item com mudança,
evidência e pendências quando for tratado. Preservar identidade visual,
componentes e PT-BR/EN.

## Por onde começar

Os dois primeiros lotes estão **implementados e validados localmente**: base de
testes/tradução/CI e edição/exclusão do diário (L04). O terceiro lote tem telas e
infraestrutura de privacidade implementadas; os textos iniciais continuam em revisão
para lançamento. Lucas confirmou **Elesys Studio LTDA** como responsável e
**lucasamorim78c@gmail.com** como contato de suporte/privacidade, e autorizou a leitura
em telas internas, pois ainda não existem URLs públicas.

L01 fica **bloqueado pela assinatura Apple Developer**, conforme Lucas. O botão
indisponível foi retirado da entrada. L06 está em andamento; Firebase e separação local estão prontos, com pendências de
Railway e Functions detalhadas abaixo. Lucas adiou a validação integrada de
homologação e autorizou seguir em lotes locais sem novos gastos. A base local
de operação (L10) foi implementada e validada. Retenção, prestadores e revisão
final dos documentos continuam pendentes; publicação web,
App Store Connect e archive assinado continuam pendentes.

| Ordem | Lote | Entrega esperada |
| --- | --- | --- |
| 1 | Base de validação — implementada | Traduções e testes locais aprovados; CI configurado, primeira execução remota pendente |
| 2 | Diário completo — implementado | Edição/exclusão do mesmo registro, permissões e retry aprovados; publicação exige migration 028/backend antes do app |
| 3 | Entrada e distribuição — implementação local pronta | Telas PT-BR/EN, contato e manifestos; textos em revisão, Apple bloqueado até assinatura Developer |
| 4 | Homologação e operação — em andamento | Ambiente separado, moderação operacional, observabilidade e QA em dois aparelhos |
| 5 | Beta do produto atual | Comunidade, diário/biblioteca e Duelo do Dia homologados; decisão de ativação do push |
| 6 | Evolução | Desempenho, offline, mídia e funcionalidades adicionais segundo evidência de uso |

A separação dos ambientes deve ocorrer antes dos testes manuais com contas e
conteúdo. A configuração Apple depende da assinatura; os documentos de privacidade devem
acompanhar as decisões operacionais antes do lançamento. Não é necessário transformar todos os demos em
funcionalidades para lançar; manter oculto ou retirar da distribuição o que não
fizer parte da primeira versão.

## Quarto lote — separação de ambientes (L06), 21/10/2026

**Decisão posterior de Lucas:** deixar a validação integrada de homologação pendente
por enquanto e avançar em trabalho local sem novos gastos. Não retomar faturamento,
provisionamento pago ou QA cloud automaticamente.

**Implementação local validada; infraestrutura de homologação parcialmente criada.**
Matriz, comandos e retomada estão em [ENVIRONMENTS.md](ENVIRONMENTS.md).

- [x] Firebase `multiverse-staging-7f87c` e app iOS próprio criados; Google e
  e-mail/senha ativos, sem copiar contas/dados/segredos de produção. Hosting
  staging publicado, associação do app validada por HTTP 200. Plano Spark mantido.
- [x] Debug instala Multiverse HML; Release conserva produção. Plists, callbacks,
  bundle, links e App Group separados, com validação no build e na inicialização.
  API de staging intencionalmente sem URL até o provisionamento; sem fallback.
- [x] API valida ambiente/projeto/credenciais/Railway, envia identidade no health
  e bloqueia header de outro ambiente antes das rotas. Migration 029 vincula banco
  vazio e impede execução/migração em banco de outro ambiente. Migrações exigem
  APP_ENV explícito; adoção de banco legado é restrita ao contexto de produção.
- [x] Local usa Compose/volume/porta próprios e Firebase demo/emulador. CI ganhou
  gate de configurações públicas; nenhum segredo de produção é necessário.
- [x] Validação: 296 testes iOS/35 suítes; 110 unitários e 160 HTTP/PostgreSQL na
  API, format/lint/tipos/build; 3 testes de configuração e 1.244 traduções.
  Release compilado sem assinatura, com Firebase/widget de produção conferidos no
  bundle; actionlint aprovado. Smoke com adaptador Admin real criou/verificou/excluiu conta no Auth emulator,
  sem e-mail. Teste Admin SDK rejeitou audience de produção em configuração staging.
  Falha de migration seguida de correção/rerun validada em PostgreSQL; Firebase
  Functions manteve seus 14 testes aprovados.
- [ ] Railway staging/Postgres/API: criação recusada por **Deploys have been paused
  temporarily**; consulta confirmou apenas production. [Incidente oficial](https://status.railway.com/)
  ainda informava API parcialmente indisponível/builds pausados na última consulta.
- [ ] Functions/Firestore/Resend/App Check próprios: projeto staging ainda Spark;
  Lucas decidiu manter sem faturamento em 21/10; deploy de Functions adiado.
  Chave Resend HML restrita autorizada, mas ainda não criada porque o armazenamento
  aprovado em Secret Manager exige faturamento. Remetente preparado localmente e
  14 testes de Functions aprovados novamente. Não houve alteração de plano.
  Google habilitado não comprova login completo com perfil/API.
- [x] Regra permanente de custos registrada em ENVIRONMENTS: sempre limitar gastos,
  exigir teto aprovado antes de novos recursos pagos e distinguir alertas de
  bloqueio efetivo. Nenhum limite financeiro novo foi configurado nos provedores.
- [ ] URL real da API, testes integrados com duas contas/dispositivos, código por
  e-mail e recuperação; assinatura Apple e capabilities continuam pendentes.

**Produção remota não foi alterada.** Nenhum commit/push/deploy da API. Antes de
uma futura publicação, definir APP_ENV=production e aplicar migrations 028/029/API
antes do app. O único deploy deste lote foi o Hosting **de homologação**.

## Quinto lote — operação local sem novos gastos (L10), 21/10/2026

**Readiness e diagnóstico implementados e validados localmente.**
Contrato e instruções em [operação da API](../backend/api/docs/operations.md).

- [x] `/health` mantém liveness; `/health/ready` confere o pool PostgreSQL e a
  identidade do ambiente, retorna 200/503 sem detalhes internos. Headers de
  segurança/no-store, cache de 5 segundos, prazo de 2 segundos e compartilhamento
  de consultas concorrentes evitam uma consulta por requisição pública.
- [x] `DatabaseModule` exporta o mesmo `DatabaseService` para aplicação e health,
  preservando Controller/Service e uma única instância do pool. Conexões de probe
  que falham/expiram são descartadas; operações normais mantêm seus limites.
- [x] `npm run ops:report` gera somente contagens/idades de exclusões, push e voz,
  com conexão explícita, verificação de ambiente e transação somente leitura.
  Sem UID, conteúdo, tokens ou erros crus; saída 0/2/1 permite triagem manual.
- [x] Testes: **117 unitários + 167 HTTP/PostgreSQL**, formatação/lint/tipos/build.
  Incluem bloqueio real de tabela, resposta 503, liveness disponível, recuperação,
  identidade divergente, cache/concorrência e relatório sem mutação/exposição de
  dados. CLI compilada validada em 6 cenários num segundo PostgreSQL descartável.
  1.244 traduções e 3 testes de configuração também aprovados.
- [x] Template Railway preparado para `/health/ready` em publicação futura;
  configuração remota e produção não foram alteradas. Nenhum serviço contratado,
  envio de e-mail/push ou chamada a provedor externo nesta validação.
- [ ] Monitoramento/alertas hospedados, retenção de logs, backups/restauração e
  operação dos workers com provedores reais. L10 completo continua pendente.

Lucas autorizou push ao fechar. Commit de implementação `da37cca` publicado na
branch de revisão [codex/preparacao-lancamento](https://github.com/zUnknownUser/Multiverse/tree/codex/preparacao-lancamento),
incluindo lotes locais anteriores desta conversa. Master preservada, sem acionar
seu autodeploy de produção. Primeira execução remota de CI continua pendente.

## Terceiro lote — implementação em 21/10/2026

- Mesma `LegalDocumentView` na navegação AuthRoute/Route existente; `Core/Legal`
  carrega recursos locais usando `L10n`, sem depender de conta/API. Fundo papel,
  fontes/tokens, botão voltar e cards seguem o DesignSystem. Textos PT-BR/EN em
  recursos próprios, além das traduções dos controles no catálogo existente.
- Identificação confirmada: **Elesys Studio LTDA**; suporte e privacidade em
  **lucasamorim78c@gmail.com**. O e-mail abre um rascunho no cliente escolhido pelo
  usuário, com versão do app e assunto, sem enviar automaticamente nem anexar
  dados da conta. Endereço copiável quando não houver cliente de e-mail.
- Termos cobrem conta, conteúdo, convivência, direitos e moderação. Política
  descreve autenticação, fotos, diário, interações, mensagens sem E2EE, voz,
  prestadores, dados locais, atendimento e exclusão. Ajuda explica recuperação,
  diário, denúncias/bloqueios e pedidos de dados. Não há promessa de exportação
  completa: o JSON existente contém apenas diário/reviews carregados.
- Textos identificados como **em revisão**, pois prazos de retenção e detalhes de
  prestadores ainda precisam ser fechados. `account_deletions` mantém UID/datas
  após exclusão; `moderation_decisions` mantém decisões e justificativas; não há
  expurgo automático definido. Migration 028 mantém marcadores do diário sem
  texto até exclusão da conta. Definir necessidade/prazo e executar a política
  junto à revisão de backups/provedores (L10), sem prometer exclusão absoluta.
- Manifesto app: UserDefaults `CA92.1` (preferências locais) e `1C8F.1` (App Group).
  Widget: `1C8F.1`, sem coleta própria fora do aparelho. Dados funcionais ligados
  à conta declarados no app: nome, e-mail, UID, relações sociais (Contacts, não
  leitura da agenda), mensagens, imagens, conteúdo, atividade e atendimento.
  Áudio é transmitido em tempo real, sem gravação implementada; verificar também
  a configuração real do provedor antes da declaração final. SDKs trazem seus
  próprios manifestos e devem integrar a conferência do relatório agregado.
- `FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED=true` desativa coleta mesmo em
  instalações com a antiga preferência habilitada. Não existe toggle que sugira
  um consentimento ainda não definido. Reativação exige revisar finalidades,
  retenção e declarações; autenticação/App Check continuam independentes.
- `export_legal.py` prepara seis páginas HTML com os mesmos textos, sem deploy;
  `--require-final` recusa a publicação de rascunhos ou sem responsável/contato.
  Lucas pediu telas internas nesta etapa, e nenhuma URL pública foi inventada.
- Validação automatizada: **291 testes iOS/34 suítes** aprovados, incluindo
  recursos bilíngues no bundle, mailto com caracteres especiais, contato inválido,
  manifestos no app/widget e Analytics desativado. **1.244 traduções** aprovadas.
  Renders nativos PT-BR/EN, claro/Noir em 320pt conferidos; texto da entrada
  corrigido para não truncar. Testes focados repetidos após os ajustes de layout
  aprovados. Harness visual temporário removido.

Fontes de configuração: [motivos de UserDefaults](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
[categorias do manifesto](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype),
[controle de coleta Firebase](https://firebase.google.com/docs/analytics/ios/configure-data-collection),
[App Privacy](https://developer.apple.com/app-store/app-privacy-details/),
[direitos dos titulares/ANPD](https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1/direito-dos-titulares).
As fontes orientam a preparação; não representam homologação dos serviços ou aprovação
jurídica/do App Review. Nenhum deploy, commit, push ou envio de e-mail foi feito.

## Segundo lote — diário concluído em 21/10/2026

- Menu de cada registro com editar/excluir. Edição conserva UUID/obra e carrega
  nota, data, texto original, Curti, Revisitei e spoiler do registro exato,
  sem confundir releituras nem salvar textos de apresentação como review.
- `PATCH /me/diary/:id` exige registro próprio existente. `DELETE` confirma o
  UUID removido e retorna estado atualizado; exclusão pede confirmação no app.
  Review, comentários, reações e notificações vinculadas são removidos juntos.
- Migration 028 mantém um marcador sem texto para retry e impede que PUT/PATCH
  atrasado recrie o registro. Exclusão da conta remove os marcadores. A trava
  transacional por conta existente continua coordenando as escritas.
- Estatísticas são devolvidas mesmo ao apagar o último registro da obra.
  Histórico, perfil, favoritos derivados, feed e progresso refletem o estado
  confirmado; vistos manuais permanecem independentes. Respostas antigas não
  desfazem a mudança. Falha conserva rascunho/ação pendente; refresh resolve uma
  exclusão já confirmada que perdeu a resposta antes de atualizar o restante.
- Padrões mantidos: controllers validam HTTP; service aplica regras/transações;
  `ActivityAPI`/cliente adaptam endpoints; AppStore coordena estado; views usam
  ambiente, tokens e componentes existentes. Contrato em
  [activity.md](../backend/api/docs/activity.md).
- Validação: API format/lint/tipos/build, 99 unitários e 155 HTTP/PostgreSQL;
  iOS 287 testes em 33 suítes; 1.227 traduções validadas. Renders nativos em 320pt,
  PT-BR/EN, claro/Noir conferidos; harness visual temporário removido.

**Publicação:** aplicar `028_diary_entry_deletions.sql` e publicar a API antes do
novo app, que valida `entryId` nas reviews privadas. Nenhum deploy, commit ou push
foi feito neste lote. CI remoto e QA físico continuam pendentes em L07/L09.
Edições simultâneas seguem a ordem de gravação no servidor; o contrato não oferece
mesclagem automática entre aparelhos. Diário continua sem paginação e rascunho
persistido offline, conforme E03/E04.

## Primeiro lote — entrega em 21/10/2026

- L08 concluído: `%@/2000` traduzido em PT-BR/EN; 1.214 entradas aprovadas.
- L07 implementado: [workflow](../.github/workflows/ci.yml), comandos locais com
  PostgreSQL 18 descartável e [guia de testes](TESTING.md). `make test` inclui
  localização e verificação completa da API.
- API: formatação, lint, tipos, build, 99 unitários e 149 HTTP/PostgreSQL aprovados.
  URL ausente/inválida e conexão indisponível retornam erro antes das suítes.
  `make api-test` também passou com variáveis de aplicação inválidas herdadas,
  confirmando o isolamento e a substituição da URL pelo banco temporário.
- Banco local removido após sucesso, falha do comando (código 42 preservado) e
  SIGTERM (código 143). Cada suíte continua isolando migrations em seu schema.
- Firebase: 14 testes aprovados. iOS: 279 testes/33 suítes aprovados no simulador,
  com assinatura desativada e URL da API em localhost no build de teste.
- Workflow validado por actionlint 1.7.12. Instalações limpas (`npm ci`) em
  containers Linux também aprovadas: Node 24.22.0/API (99 + 149 testes, além
  de formatação/lint/tipos/build) e Node 22.23.3/Firebase (14 testes).

O iOS local foi validado com Xcode 27 beta/iOS 27; o runner configurado usa Xcode
26.6/iOS 26.5 conforme a imagem oficial. A combinação remota ainda precisa passar
no GitHub. Nenhum push/deploy ou regra de branch foi alterado neste lote.
Mudanças locais anteriores foram preservadas. As integrações externas e QA físico
continuam com os limites registrados abaixo, e L06 (homologação separada) permanece
pendente.

## Evidência da auditoria inicial

| Verificação em 21/10/2026 | Resultado |
| --- | --- |
| Build e testes iOS no simulador | 279 testes em 33 suítes passaram |
| API formatação, lint, tipos e build | Passaram |
| API unitários | 99 passaram |
| API HTTP com PostgreSQL temporário | 149 passaram |
| Firebase Functions | 14 passaram |
| Catálogo de tradução | 1.214 entradas; verificação falhou na entrada vazia `%@/2000` |

Na API, a primeira execução sem acesso a portas locais foi impedida pelo sandbox.
Com acesso local e banco temporário, a execução paralela teve timeouts de preparação
em sete suítes. A repetição em série, com `--no-file-parallelism --hookTimeout=60000`,
passou completa. Tratar a previsibilidade da execução sem atribuir esses timeouts
a uma falha funcional comprovada. O banco temporário foi encerrado ao final.

Os testes HTTP usam PostgreSQL real e identidades/provedores externos controlados.
Esta rodada não homologou entrega de e-mail, APNs, compras, App Attest Release ou
voz entre iPhones. Não auditou configuração atual de backups nem o estado do deploy
em produção. Nenhum código do produto, serviço externo ou deploy foi alterado na
auditoria; modificações locais preexistentes foram preservadas.

## O que já tem implementação real

“Real” indica integração e persistência implementadas, não homologação de todos
os provedores em produção. A composição está em
[RootView](../apps/ios/Multiverse/App/RootView.swift).

| Área | Implementação atual |
| --- | --- |
| Google e e-mail | Firebase Authentication, confirmação por código e recuperação por link |
| Conta e perfil | Username, perfil, foto, onboarding e exclusão com API/PostgreSQL |
| Catálogo Marvel/DC | Obras, séries, capas, agregados e fontes externas; acervo inicial limitado |
| Diário | Notas, registros, reviews, releituras e edição/exclusão individual persistidos |
| Biblioteca | Desejos, favoritos e listas privadas persistidos |
| Social | Pessoas, follows, feed, comentários, reações, privacidade, bloqueios e denúncias |
| Comunidade | Posts, imagens, respostas, menções, teorias e duelos |
| Clubes e salas | Membros, programação, progresso e conversas |
| Mensagens privadas | Texto, cartas, pedidos e leitura |
| Duelo do Dia | Votos, ranking, pontos, títulos e fila editorial com sugestões |
| Voz | Integração LiveKit; microfone físico, Bluetooth e interrupções ainda exigem QA |
| Atividade | Notificações internas, leitura e contador; push remoto tem ativação separada |

## Pendências antes do lançamento público

As prioridades abaixo representam a proposta da auditoria, não uma declaração de
que todas são exigências da loja. Requisitos externos devem ser conferidos no
momento da distribuição.

| ID | Estado | Achado e ação | Critério para concluir |
| --- | --- | --- | --- |
| L01 | Bloqueado externamente (21/10/2026) | Lucas ainda não assinou Apple Developer. Botão Apple retirado de Boas-vindas para não oferecer um fluxo que sempre falha; implementação e configuração permanecem pendentes. | Após assinatura, implementar e homologar login/cancelamento/contas/sessão e revisar regra 4.8 antes da distribuição. Ocultar o botão não conclui o requisito de lançamento. |
| L02 | Implementado localmente; textos/publicação pendentes (21/10/2026) | Termos, política e ajuda internos, offline e PT-BR/EN, acessíveis antes do login e nos Ajustes. Responsável/contato confirmados por Lucas; mailto revisável, copiar e-mail e tratamento de app de e-mail indisponível. | Fechar revisão dos textos (retenção/prestadores de L03/L10, bases legais e público-alvo), publicar documentos em HTTPS para distribuição e validar atendimento real. Conteúdo atual é versão inicial explicitamente em revisão. |
| L03 | Implementado parcialmente (21/10/2026) | Manifestos próprios do app/widget e inventário de dados preparados. Analytics desativado no plist com precedência sobre preferências antigas; removida ativação na inicialização. | Manifestos incorporados ao build/testados. Falta revisar retenção/backups/transferências/configuração dos SDKs, relatório agregado de archive assinado e formulário App Privacy no App Store Connect. |
| L04 | Concluído localmente (21/10/2026) | Menu de edição/exclusão, formulário preenchido pelo UUID, DELETE confirmado/idempotente e proteção contra gravação atrasada. Arquitetura e componentes existentes preservados. | API: 99 unitários + 155 HTTP; iOS: 287 testes/33 suítes; traduções e renders PT-BR/EN claro/Noir em 320pt aprovados. Publicar migration 028/API antes do novo app; QA físico segue em L09. |
| L05 | Pendente | Denúncias/bloqueios e CLI auditada existem; operação humana e filtragem preventiva precisam ser completadas. | Responsável e rotina de atendimento definidos, fila utilizável, política de filtragem/moderação aplicada e contato público. Painel, comunicação de decisões e contestação planejados conforme escala. |
| L06 | Validação integrada adiada (21/10/2026) | Código validado; Firebase/Auth/Hosting staging criados, Debug/Release e identidade do banco separados. Lucas pediu deixar a validação pendente e seguir em trabalho local sem novos gastos. | API/Postgres pendentes de disponibilidade e orçamento; Functions adiadas por decisão de manter Spark sem faturamento. Configuração e QA integrado pendentes. Ver [guia](ENVIRONMENTS.md). |
| L07 | Implementado; validação remota pendente | CI versionado com tradução/API/Firebase/iOS; PostgreSQL descartável local e no job. Falha explícita sem URL/banco, setup isolado e execução HTTP serial. | Verificações locais passaram; workflow aprovado pelo actionlint. Conferir a primeira execução GitHub após push. Regras de branch e autodeploy são configurações remotas separadas. |
| L08 | Concluído (21/10/2026) | Entrada `%@/2000` preenchida em PT-BR/EN, preservando o placeholder e as mudanças locais. | Verificador aprovado: 1.214 entradas, placeholders e referências conferidos. |
| L09 | Pendente | Falta homologação física completa e validação do pacote de distribuição. | Duas contas/aparelhos cobrem cadastro/código/reenvio, recuperação, login/logout/troca, exclusão, mensagens, bloqueios, fotos e voz; assinatura Release, App Attest, links e TestFlight conferidos. |
| L10 | Base local implementada (21/10/2026) | Readiness do banco e relatório privado das pendências de exclusão/push/voz, sem novos gastos. API: 117 unitários + 167 HTTP/PostgreSQL e 6 cenários da CLI aprovados. | Monitoramento remoto, alertas, retenção de logs, backups/restauração e QA com provedores continuam pendentes. Ver [contrato operacional](../backend/api/docs/operations.md). |

Evidências principais:

- [Login Apple](../apps/ios/Multiverse/Core/Auth/FirebaseAuthRepository.swift),
  [boas-vindas](../apps/ios/Multiverse/Features/Auth/WelcomeView.swift) e
  [Analytics](../apps/ios/Multiverse/App/MultiverseApp.swift).
- [Diário](../apps/ios/Multiverse/Features/Diary/DiaryView.swift),
  [AppStore](../apps/ios/Multiverse/Core/AppStore.swift) e
  [ActivityController](../backend/api/src/activity/activity.controller.ts).
- [Configuração iOS](../apps/ios/project.yml), [Makefile](../Makefile),
  [verificador PT-BR/EN](../apps/ios/scripts/check_localization.py) e
  [catálogo de tradução](../apps/ios/Multiverse/Resources/Localizable.xcstrings).
- [Moderação](../backend/api/scripts/moderate.mjs),
  [healthcheck](../backend/api/src/health/health.controller.ts) e
  [retomada de autenticação](../backend/firebase/PENDING_SETUP.md).

Confirmar também a resolução da rotação de credencial de e-mail registrada em
PENDING_SETUP; o estado atual da rotação não foi verificado. Não copiar credenciais
para esta documentação.

## Mocks e funcionalidades preparadas

As rotas e atalhos demonstrativos são em grande parte ocultos/bloqueados nas contas
reais. Existem versões legadas de clubes, salas, teorias, duelos e mensagens junto
das versões novas integradas. Não classificar o módulo inteiro como mock apenas
por encontrar a tela antiga. Preservar mocks necessários aos testes.

| ID | Recurso | Estado observado | Tratamento sugerido |
| --- | --- | --- | --- |
| M01 | Wrapped | Setembro/2026 fixo, comparação por fórmula e arquétipo predefinido | Manter oculto; implementar períodos/dados reais antes de oferecer |
| M02 | Previsões e liga | Perguntas, pontos, respostas e ranking demo | Segunda fase, com regras de apuração e persistência |
| M03 | Debate da semana antigo | Conteúdo e contagens fixos, voto local | Manter fora do fluxo real ou substituir por posts/duelos existentes |
| M04 | Afinidade | Percentuais por seed | Só oferecer após definir cálculo com histórico real e privacidade |
| M05 | Cronologia e conexões | JSON local, sem grafo editorial remoto completo | Curadoria e modelo remoto antes de exposição |
| M06 | Escudo cronológico automático | Timeline/progresso local | Manter distinto da proteção real de spoilers explicitamente marcados |
| M07 | Onde assistir/comprar e alertas | Disponibilidade demo; alerta não cria assinatura remota | Exigir fonte real, atualização e operação de alertas; afiliados continuam adiados |
| M08 | Sugerir correção | Formulário/memória sem fila editorial remota | Criar submissão, acompanhamento e revisão antes de expor |
| M09 | Badges antigos de universo | Cálculo local/demo | Não confundir com títulos reais do Duelo do Dia |
| M10 | Widgets | Extensão existe, mas sessão real não publica snapshot | Integrar dados reais ou retirar da versão distribuída até ficar útil |
| M11 | Estreia e Live Activity | Estrutura/layout sem operação completa de estreia | Segunda fase |
| M12 | Pro | StoreKit 2 e configuração de testes; venda/vínculo ao UID incompletos | Monetização segue adiada; definir autoridade de entitlement, produtos, restauração e benefícios reais antes de ativar |
| M13 | Push fechado | Implementação preparada; projeto padrão desabilitado | Configurar APNs/build/Firebase e homologar entrega antes de anunciar |
| M14 | Telas legadas sociais | Mensagens, clubes, salas, teorias e duelos antigos usam exemplos | Isolar de produção e preservar apenas o que for útil a testes/previews |

Fontes: [MockRepository](../apps/ios/Multiverse/Core/Repository/MockRepository.swift),
[StaticContent](../apps/ios/Multiverse/Core/StaticContent.swift),
[Logic](../apps/ios/Multiverse/Core/Logic.swift),
[navegação](../apps/ios/Multiverse/Core/Navigation.swift),
[ProStore](../apps/ios/Multiverse/Core/Store/ProStore.swift) e
[WidgetBridge](../apps/ios/Multiverse/Core/Store/WidgetBridge.swift).

## Melhorias técnicas e de produto

| ID | Estado | Melhoria | Resultado esperado |
| --- | --- | --- | --- |
| E01 | Pendente | Remover carregamento demo da composição normal | Sessão real não carrega fixtures/módulos ocultos nem latência artificial de 220 ms; previews/testes preservados |
| E02 | Pendente | Dividir AppStore, hoje com cerca de 2.000 linhas | Estado de diário, onboarding, navegação e legado com responsabilidades claras; aproveitar stores já existentes |
| E03 | Pendente | Paginar diário e carga inicial de catálogo | Evitar snapshots completos crescentes; salvar registro não precisa retornar todo histórico; preservar progresso/estatísticas corretos |
| E04 | Pendente | Leitura offline e rascunhos persistentes | Últimos dados e rascunhos sobrevivem ao relançamento; fila/retry com isolamento por conta e idempotência definidos |
| E05 | Pendente | Evoluir armazenamento de imagens | Planejar object storage e entrega autorizada antes da escala; manter bloqueios, exclusão e privacidade ao sair de PostgreSQL/base64 |
| E06 | Pendente | Proteção geral contra excesso de requisições | Complementar limites por ação; verificar proteção já existente no provedor antes de configurar limites globais |
| E07 | Parcial | README raiz e guia de testes criados no primeiro lote; restante da documentação ainda precisa de revisão | Entrada e comandos atualizados; falta revisar descrições legadas de recursos já integrados e separar todo o histórico |
| E08 | Pendente | Instrumentar o ciclo principal de uso | Medir cadastro concluído, primeiro registro/post/voto, conversas respondidas e retorno; respeitar declarações/preferências de dados |
| E09 | Pendente | Operar a fila editorial do Duelo do Dia | Reposição e acompanhamento de estoque; sem prometer geração infinita ou repetir conteúdo automaticamente |
| E10 | Pendente | Facilitar começar e acompanhar conversas | Validar descoberta, primeira participação, resposta e retorno com usuários; manter follows opcionais e evitar redesenho sem necessidade |
| E11 | Pendente | Conferir limites das funcionalidades atuais | Listas privadas, DMs sem mídia/edição/exclusão individual, clubes sem coorganizador/expulsão/transferência e perfis remotos sem histórico público completo devem estar claros no escopo |

O catálogo inicial e as ordens editoriais são limitados; não equivalem a todo o
cânone. A descoberta atual não é um ranking personalizado. Priorizar qualidade,
curadoria e o ciclo social sobre expansão indiscriminada de catálogo.

Para a primeira versão, a direção sugerida é comunidade Marvel/DC apoiada por
diário/biblioteca e Duelo do Dia. Wrapped, previsões, afinidade, cronologia avançada
e monetização ficam depois. RevenueCat e afiliados continuam apenas documentados
no [backlog](BACKLOG.md), conforme decisão anterior; revisar licença comercial das
fontes antes de monetizar.

## Referências externas

Consultadas na auditoria de 21/10/2026; revalidar ao implementar/publicar.

- [Apple login e regra 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services).
- [Apple privacidade](https://developer.apple.com/app-store/review/guidelines/#privacy).
- [Apple conteúdo de usuários](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
- [Apple UserDefaults e manifesto de privacidade](https://developer.apple.com/documentation/foundation/userdefaults).
- [TMDB uso comercial e atribuição](https://developer.themoviedb.org/docs/faq).

## Histórico de tratamento

- 21/10/2026: auditoria e prioridades registradas a pedido de Lucas; nenhum item
  funcional desta lista implementado neste registro.

- 21/10/2026: L08 concluído; correção pontual do contador de mensagens. L07 em
  implementação: banco temporário, falha explícita sem banco e pipeline.

- 21/10/2026: L07 implementado e validado localmente; CI remoto ainda pendente.
  Instalações limpas em Linux/Node 24 e 22 aprovadas. E07 avançou parcialmente
  com README e guia de testes. Próximo lote sugerido: L04.

- 21/10/2026: L04 iniciado a pedido de Lucas, preservando arquitetura e padrões.
  Contrato: edição do mesmo UUID, exclusão confirmada/idempotente, vínculo exato
  review–registro e reconciliação de estatísticas/progresso.

- 21/10/2026: L04 implementado; API aprovada com 99 unitários + 155 HTTP.
  Suíte iOS inicial aprovada com 286 testes; conferência visual e proteção
  adicional da atualização após exclusão sem resposta em validação final.

- 21/10/2026: L04 concluído localmente. Regressão final iOS: 287 testes/33 suítes;
  API: 99 + 155; tradução: 1.227; renders estreitos conferidos. Migration 028 e
  backend devem preceder o app na publicação. Próximo lote sugerido: L01–L03.
