# Inventário de dados reais e demonstrações — 03/10/2026

Auditoria atualizada após ordens de leitura (migration 021), mensagens privadas, voz nas salas e escopo Marvel/DC. “Demonstração”
significa dados de exemplo ou interação que não chega a outro usuário/servidor.
Uma função local pode funcionar de verdade sem ser sincronizada. A distinção abaixo
considera a sessão autenticada normal, não previews/testes com repositórios mockados.

## Navegação atual

A sessão autenticada usa Home, Busca, Biblioteca e Perfil. A Biblioteca substitui
Clubes na barra: desejos, favoritos e listas privadas agora persistem na conta.
Os módulos demonstrativos descritos abaixo permanecem no código para previews e
trabalho futuro, mas seus atalhos foram ocultados e suas rotas bloqueadas na sessão
real. As abas de universo mostram Geral, Ordens e Personagens; a timeline
continua oculta. Clubes, salas, teorias e duelos reais são acessados pela Comunidade;
salas também pela obra. As telas legadas desses módulos não são usadas pela conta real. Pro, Wrapped, escudo automático por cronologia e ações sem backend
também saíram dos acessos normais. Spoilers explícitos continuam funcionando.
Widgets não recebem mais snapshots mistos em sessões reais: ficam sem dados.
Capas gráficas/avatares de iniciais e estatísticas locais descritas abaixo continuam
sendo apresentação/cálculo local; não são novos serviços de mídia ou medição.

## O que já usa backend real

- Login Google/e-mail, verificação/recuperação, perfil/@usuário, onboarding e exclusão:
  Firebase Authentication + API/PostgreSQL; fluxo de e-mail via funções/Resend.
- Catálogo de universos/obras e descrições PT/EN, busca sobre o acervo carregado,
  médias/histogramas e quantidades de registros: dados publicados no PostgreSQL.
  Universo “membros” conta onboarding real; o contador de presença foi ocultado.
- Diário, notas, revisitas, reviews e favorito escolhido **dentro do registro**:
  persistidos na conta; histórico e contadores pessoais não recebem amostras.
- **Ordens de leitura:** três percursos editoriais Marvel/DC em PT-BR/EN no banco,
  seguir/votar/desfazer por conta e contagens reais. Progresso usa obras distintas do
  diário, com próxima leitura; checks locais não concluem etapas.
  [Contrato, referências e limites](../backend/api/docs/reading-orders.md).
- **Capas:** URLs reais das fontes já vinculadas, com imagens nos cartões existentes, cache e fallback. [Contrato e cobertura](../backend/api/docs/catalog-covers.md).
- **Séries de HQs:** agrupamento real das edições publicadas, ordenação numérica e
  progresso por obras distintas do diário, sem duplicar releituras.
- **Biblioteca privada:** desejos e favoritos por obra, criar/editar/excluir listas,
  adicionar/remover obras, leitura sincronizada e proteção contra concorrência/retry.
  Limites: 50 listas, 200 obras/lista e 1.000 obras entre desejos/favoritos.
  Favoritos anteriores derivados do último registro do diário são migrados uma vez;
  depois, coração da obra e “gostei” do diário são independentes.
- Pessoas, busca/sugestões, perfil básico, seguir/deixar de seguir e contadores:
  API real. Perfis remotos não recebem afinidade, favoritos ou estatísticas fictícias.
- Feed de reviews de quem você segue, opt-in de diário público, comentários,
  curtidas, reações, permissão de comentários, bloqueios e denúncias: reais.
- **Posts da comunidade**: texto, edição pelo autor, até quatro imagens, spoiler,
  comentários/respostas vinculadas, menções com seletor e aviso no sino, reações,
  denúncia/bloqueio e exclusão. Busca textual e filtros recentes/seguidos/em conversa.
- **Clubes reais:** criação/edição/exclusão, entrar/sair, membros, calendário por obra,
  progresso por membro/etapa, discussões, convite por link e denúncia/moderação.
- **Salas reais:** uma por obra publicada; mensagens, respostas, reações, presença
  por visitas no último minuto e progresso sincronizado; trechos 0/50/100 com proteção
  no servidor. Atualização por eventos do banco enquanto a sala está aberta, com reconexão e aviso de novas mensagens.
- **Voz nas salas:** LiveKit nativo, entrada explícita com microfone desligado; chat
  independente, até 8 participantes e desconexão ao sair/background. Falta QA físico
  de microfone/Bluetooth/interrupções em iPhones.
- **Mensagens privadas:** conversas 1:1, pedidos/aceite/recusa, texto, cartas de obras,
  spoiler, leitura/não lidas, paginação, bloqueios, denúncias e sino reais. Atualização
  por eventos enquanto o app está ativo. [Contrato e limites](../backend/api/docs/private-messages.md).
- **Teorias e duelos reais:** publicação, descoberta, votos únicos por conta e contagens
  persistidas. Teoria tem conclusão identificada como decisão do autor com explicação;
  duelo tem opções e prazo. Nada de votos-base, ranking ou precisão inventada.
- **Central de atividade e sino**: eventos novos reais de follows/comentários/reações,
  estado de leitura persistido, paginação e preferências por conta. Atualização em
  primeiro plano a cada 30s, ao voltar e por gesto; não é uma conexão em tempo real.
- Fila/revisão de denúncias de reviews, posts, comentários, clubes e mensagens: CLI privada no banco,
  decisões auditadas. Precisa de operação humana, sem painel web ou IA automática.

Fontes: [RootView](../apps/ios/Multiverse/App/RootView.swift),
[AppStore](../apps/ios/Multiverse/Core/AppStore.swift),
[API social](../backend/api/src/social), [posts](../backend/api/src/community),
[atividade](../backend/api/src/notifications).

## Demonstrações mantidas no código, ocultas na sessão real

| Área/tela | O que ainda é exemplo/local, exatamente |
| --- | --- |
| Clubes (legado/demo) | Fixtures de `recursos-data.json`, cutucada sem entrega e cards antigos continuam apenas em previews. O módulo acessível pela Comunidade usa backend real; não inclui lembretes por push. |
| Salas (legado/demo) | As telas antigas com trechos editoriais, pin de teoria fixa e contagens de exemplo permanecem isoladas. As salas acessíveis pela Comunidade/ficha da obra usam posts, presença e progresso reais. |
| Estreia ao vivo | Evento/banner, contador, enquete relâmpago, votos e chat/stickers gerados por timers: simulação local. Não acompanha uma estreia real nem transmite mensagens. |
| Mensagens privadas (legado/demo) | Desafios por DM, grupos, afinidade e status “online agora” das telas antigas continuam apenas no repositório de demonstração. Conversas, pedidos, texto, cartas e leitura agora são reais nas novas telas. |
| Duelo do dia (legado/demo) | O card antigo, rotação de exemplos, votos-base e desafio por DM continuam ocultos. Duelo criado pela Comunidade tem votos e encerramento reais; não há seleção automática diária. |
| Debate da semana | Assunto/opções, números de votos e “612 comentários” fixos. Voto local, sem debate multiusuário no backend. |
| Teorias (legado/demo) | Precisão, pontos de lore, revisores fictícios e teorias de exemplo continuam isolados. Teorias acessíveis na Comunidade têm conteúdo/votos reais e conclusão do autor explicitamente identificada. |
| Previsões | Eventos/perguntas, respostas, pontos e liga/ranking: exemplos/memória. Não há apuração real nem competição compartilhada. |
| Check de visto fora do diário | Após onboarding, check/uncheck em ordem/timeline usa estado local. O diário real marca a obra vista ao recarregar; desmarcar localmente não exclui um registro. Os vistos escolhidos no onboarding são persistidos naquele fluxo. |
| Ordens de leitura (legado/demo) | JSON antigo, autores fictícios, votos-base e checks locais continuam só em previews. A sessão real usa percursos editoriais no banco e progresso do diário. Criação/edição comunitária de ordens ainda não foi implementada. |
| Linha do tempo | Eras, posição e vínculos com obras vêm do JSON. Não há cronologia editorial completa no banco; obras novas importadas não ganham automaticamente posição. A navegação entre itens existentes funciona. |
| Mapa de conexões | Relações entre obras/personagens são fixas no JSON. O mapa desenha/navega, mas não há grafo de relações remoto atualizado. |
| Cânone / essencial ou pulável | Rótulos editoriais específicos vêm de tabelas locais; contagens das enquetes são geradas por seed e voto em memória. Não representam votação real da comunidade. O campo básico de cânone da obra existe no catálogo remoto. |
| Onde assistir / leia antes | Serviços, disponibilidade, observações e links vêm de `recursos-data.json`; não há consulta atual de streaming/estoque. O toggle “me avise quando entrar num serviço que assino” é `@State`: não cria alerta. O aviso de afiliado não comprova integração/rastreamento comercial. |
| Sugerir correção | Formulário e lista local de sugestões funcionam em memória; não chegam a uma fila editorial remota nem alteram catálogo. |
| Wrapped | Recorte fixo em setembro/2026; registros/horas/notas usam parte do diário real, mas comparação com agosto usa fórmula fixa, arquétipo “O Arquivista”/82% é fixo, e existem fallback de obra/nota/universo. Não é retrospectiva mensal/anual completa e confiável. A imagem de compartilhamento renderiza esses mesmos dados mistos. |
| Rankings e afinidade | Liga de previsões, precisão de teoristas e personas demo são fixos. A antiga lista “top loristas da semana” e notificações fictícias permanecem declaradas em `StaticContent`, mas **não são mais exibidas na central real**. Compatibilidade/progresso de perfis demo usa seed; perfis de pessoas reais omitem esses cartões. Não há algoritmo real de afinidade/ranking. |
| Badges de universo | No perfil demonstrativo, o progresso é calculado localmente a partir do acervo/“visto”; badge é liberado pelo limiar de 50%. Não existe concessão/histórico de badge no servidor. Em personas demo, progresso pode ser calculado por seed. |
| Widgets | Ponte App Group e isolamento/limpeza por sessão estão implementados. Snapshot legado é misto e deixou de ser publicado em sessões reais: progresso local/diário + ordem e duelo de amostra; delta do universo é fixo `3`. O widget não é prova de backend para duelo/ordens. |
| Live Activity | Extensão/layout, atributos e solicitação/atualização local via ActivityKit existem. Não há operação remota de estreia/APNs ActivityKit; tela de estreia continua simulada. |
| Capas/avatares | Capas reais via TMDB/Metron nos 33 vínculos conferidos (30 edições + três filmes/séries), com cache e fallback gráfico. Obras sem vínculo, incluindo DC/personagens nesta etapa, mantêm a arte anterior. Avatares continuam com iniciais; foto de perfil ainda não implementada. |

Fontes principais: [MockRepository](../apps/ios/Multiverse/Core/Repository/MockRepository.swift),
[StaticContent](../apps/ios/Multiverse/Core/StaticContent.swift),
[Logic](../apps/ios/Multiverse/Core/Logic.swift),
[AppStore](../apps/ios/Multiverse/Core/AppStore.swift),
[telas de funcionalidades](../apps/ios/Multiverse/Features),
[WidgetBridge](../apps/ios/Multiverse/Core/Store/WidgetBridge.swift).
Em geral, mutações em `MockRepository` se perdem quando o repositório é recriado;
não prometem persistência entre sessões/dispositivos.

## Funciona localmente, mas não equivale a serviço pronto

- **Escudo de spoiler:** regra e revelação existem, usando timeline fixa e ponto/progresso
  local; ajuste não sincroniza entre dispositivos. Spoiler explícito de reviews/posts/
  comentários é respeitado pelos respectivos fluxos. O toggle global “Esconder spoilers”, sem efeito nas regras atuais, foi ocultado nos Ajustes.
- **Temas claro/escuro/sistema:** implementados com `UserDefaults`, não são falsos.
  Fonte, cores, animações, navegação e localização PT-BR/EN também são implementações reais.
- **Estatísticas Pro:** frequência/sequence, notas e registros derivam do diário;
  horas por universo usam duração estimada por tipo (`Logic.loreHours`), sem cronômetro.
- **StoreKit:** compra/restauração/entitlement verificado e tratamento de oferta existem.
  O esquema usa `Products.storekit` para testes. Sem Apple Developer/App Store Connect
  configurados e teste em dispositivo, não há venda de produção validada. O Pro não está
  vinculado ao UID Multiverse nem validado no backend; Wrapped anual prometido no material
  não é uma retrospectiva anual implementada.
- **Alterar senha nos Ajustes:** linha visual sem ação, agora oculta. Recuperação pela tela de login é
  um fluxo distinto, implementado; não confundir os dois.

## Preparado ou limitado por escopo, não “mock funcionando”

- **Push com app fechado:** código iOS/API e fila preparados; desativado por decisão do
  usuário, que ainda não tem Apple Developer. Faltam credencial APNs no Firebase,
  provisioning/build habilitado e validação de entrega em iPhone. Testes simulam FCM;
  não demonstram entrega real. [Passo a passo de ativação](../backend/api/docs/community-notifications.md).
- **Ordens de leitura:** seleção inicial de três percursos; não é cronologia completa.
  Sem criação comunitária, comentários, widget real ou equivalência automática entre
  volumes e edições avulsas. Curadoria/publicação administrativa; retry só na sessão.
- **Mensagens privadas:** somente texto e cartas, sem mídia/áudio/grupos ou edição/
  exclusão individual. Rascunho/retry não persistem ao encerrar o app. Pedidos recusados
  não podem ser recuperados nesta versão. Push depende de APNs, como descrito acima.
- **Biblioteca:** listas privadas, sem colaboração/compartilhamento público, curtidas,
  ordenação manual ou busca no servidor. O seletor pesquisa o catálogo carregado.
  Requer rede para gravar; retry mantém a identidade enquanto a sessão está aberta,
  sem fila offline durável após encerrar o app. Ao reabrir, consulta o estado remoto.
  As antigas listas editoriais e seus contadores de amostra não foram migrados.
- **Catálogo:** acervo inicial publicado é real, mas pequeno e incompleto. Home mostra
  seleção do catálogo, não ranking por tendência. O backend retorna `live=0`, sem presença.
  O produto está limitado a Marvel/DC; os demais universos foram removidos/arquivados.
- **Marvel:** revisão/importação com Wikidata/TMDB existe; não significa catálogo completo
  nem atualização editorial automática. Metron agora publica 30 edições revisadas de quatro séries, com ficha PT-BR/EN; sem páginas de leitura, capas ou catálogo completo.
- **Reviews de outras pessoas por obra/perfil:** o feed de seguidos e o detalhe funcionam;
  a seção de obra é rotulada “suas reviews”. Não há catálogo global de reviews de todos,
  nem página de histórico público completo no perfil remoto. Nenhuma amostra deve preencher
  esses estados vazios.
- **Comunidade:** recursos solicitados ligados ao backend; sem reposts, vídeo, ranking
  personalizado, fila offline durável, DMs ou live de estreia. Clubes são públicos,
  sem coorganizador/expulsão/transferência. Teorias não têm validação editorial automática
  nem pontos/ranking. Salas usam long polling acordado por eventos do banco; com voz nativa opcional via LiveKit, sem vídeo, WebSocket para o chat ou indicador de digitação.
  As amostras antigas não foram publicadas no servidor. Imagens ficam no PostgreSQL
  com limites; object storage/CDN é evolução necessária antes de escala de mídia.
  [Contrato e limites detalhados](../backend/api/docs/live-community.md).
- **Notificações novas:** somente ações novas suportadas; não reconstrói todo histórico,
  não cobre módulos demo, não envia e-mail de atividade. Marcar lidas atua em até 100 IDs
  carregados por vez. Preferência desativada bloqueia novos eventos, não apaga histórico.
- **Moderação:** CLI manual auditada, sem painel, contestação, notificações de decisão ou
  IA automática. O endpoint de IA preparado no backend não modera os posts do app.
- **Operação de produção:** health é liveness, não prontidão do banco/Firebase. Paginação
  completa do diário/carga inicial de catálogo, monitoramento e política de retenção de
  atividade ainda precisam evoluir antes de escala. Testes automatizados usam identidades
  controladas; falta homologação manual de ponta a ponta com duas contas reais.

## Validação desta entrega

178 testes iOS; 75 unitários + 100 HTTP/PostgreSQL na API; PT/EN verificado (1034 entradas).
Build normal e testes executados em simulador. O build opt-in de push foi compilado no lote anterior, sem envio real. O inventário é auditoria do
código; não afirma homologação em aparelho nem uso real de integrações ainda não ativadas.
