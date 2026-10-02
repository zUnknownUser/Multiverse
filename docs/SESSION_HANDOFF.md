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
