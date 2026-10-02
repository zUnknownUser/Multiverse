# Inventário de dados reais e demonstrações — 02/10/2026

Auditoria do código após posts de comunidade e central de atividade. “Demonstração”
significa dados de exemplo ou interação que não chega a outro usuário/servidor.
Uma função local pode funcionar de verdade sem ser sincronizada. A distinção abaixo
considera a sessão autenticada normal, não previews/testes com repositórios mockados.

## O que já usa backend real

- Login Google/e-mail, verificação/recuperação, perfil/@usuário, onboarding e exclusão:
  Firebase Authentication + API/PostgreSQL; fluxo de e-mail via funções/Resend.
- Catálogo de universos/obras e descrições PT/EN, busca sobre o acervo carregado,
  médias/histogramas e quantidades de registros: dados publicados no PostgreSQL.
  Universo “membros” conta onboarding real; “ativos agora” ainda é zero fixo.
- Diário, notas, revisitas, reviews e favorito escolhido **dentro do registro**:
  persistidos na conta; histórico e contadores pessoais não recebem amostras.
- Pessoas, busca/sugestões, perfil básico, seguir/deixar de seguir e contadores:
  API real. Perfis remotos não recebem afinidade, favoritos ou estatísticas fictícias.
- Feed de reviews de quem você segue, opt-in de diário público, comentários,
  curtidas, reações, permissão de comentários, bloqueios e denúncias: reais.
- **Posts da comunidade**: descoberta global/por universo/obra, criação de texto,
  spoiler, comentários, reações, denúncia/bloqueio e exclusão pelo autor: reais.
- **Central de atividade e sino**: eventos novos reais de follows/comentários/reações,
  estado de leitura persistido, paginação e preferências por conta. Atualização em
  primeiro plano a cada 30s, ao voltar e por gesto; não é uma conexão em tempo real.
- Fila/revisão de denúncias de reviews, posts e comentários: CLI privada no banco,
  decisões auditadas. Precisa de operação humana, sem painel web ou IA automática.

Fontes: [RootView](../apps/ios/Multiverse/App/RootView.swift),
[AppStore](../apps/ios/Multiverse/Core/AppStore.swift),
[API social](../backend/api/src/social), [posts](../backend/api/src/community),
[atividade](../backend/api/src/notifications).

## Tudo que ainda é demonstração ou mistura exemplos

| Área/tela | O que ainda é exemplo/local, exatamente |
| --- | --- |
| Clubes | Lista/clubes, membros, calendário de maratona, progresso dos participantes, discussão, mensagens, curtidas/POW: dados de `recursos-data.json` e mutações em memória. Não existe clube compartilhado no servidor. |
| Salas por obra / explorar salas | Salas, segmentos, mensagens, avatares de participantes, contagens online e progresso na conversa: exemplos/memória. Não há presença, chat ou sincronização multiusuário. |
| Estreia ao vivo | Evento/banner, contador, enquete relâmpago, votos e chat/stickers gerados por timers: simulação local. Não acompanha uma estreia real nem transmite mensagens. |
| Mensagens privadas | Conversas, pedidos, texto, cartas de obras, desafios em DM e lidas: repositório em memória. Contas reais começam sem as conversas da persona demo; os botões de mensagem/desafio no perfil remoto avisam “em breve”. Outros fluxos de cartas/desafio que chamam o repositório também não entregam a ninguém. “online agora”/afinidade na conversa são fictícios. |
| Duelo do dia | Perguntas/opções e votos-base de exemplo; seu voto só altera memória. Resultado “maioria/minoria” usa esses votos; próximo duelo troca a amostra. |
| Debate da semana | Assunto/opções, números de votos e “612 comentários” fixos. Voto local, sem debate multiusuário no backend. |
| Teorias (telas antigas) | Feed, detalhe, votos Plausível/Viajou, evidências, percentuais, pontos de lore/precisão e publicação: exemplos/memória. São um módulo separado dos posts novos, que já persistem texto real. |
| Previsões | Eventos/perguntas, respostas, pontos e liga/ranking: exemplos/memória. Não há apuração real nem competição compartilhada. |
| Listas | Listas editoriais/pessoais exibidas, autores, itens, contagens e curtidas: `sample-data.json` e memória. Não há criação/gestão/sincronização de listas por conta. |
| Quero ver/ler/jogar e coração da obra | Toggles de desejo/curtir no detalhe usam `MockRepository`, sem persistência remota. Não confundir com o campo “gostei” de um registro do diário, que é real. |
| Check de visto fora do diário | Após onboarding, check/uncheck em ordem/timeline usa estado local. O diário real marca a obra vista ao recarregar; desmarcar localmente não exclui um registro. Os vistos escolhidos no onboarding são persistidos naquele fluxo. |
| Ordens de leitura | Títulos, passos, autores e votos-base vêm do JSON; seguir ordem e votar são locais. O cálculo de progresso funciona, mas mistura passos fixos com diário/checks locais. |
| Linha do tempo | Eras, posição e vínculos com obras vêm do JSON. Não há cronologia editorial completa no banco; obras novas importadas não ganham automaticamente posição. A navegação entre itens existentes funciona. |
| Mapa de conexões | Relações entre obras/personagens são fixas no JSON. O mapa desenha/navega, mas não há grafo de relações remoto atualizado. |
| Cânone / essencial ou pulável | Rótulos editoriais específicos vêm de tabelas locais; contagens das enquetes são geradas por seed e voto em memória. Não representam votação real da comunidade. O campo básico de cânone da obra existe no catálogo remoto. |
| Onde assistir / leia antes | Serviços, disponibilidade, observações e links vêm de `recursos-data.json`; não há consulta atual de streaming/estoque. O toggle “me avise quando entrar num serviço que assino” é `@State`: não cria alerta. O aviso de afiliado não comprova integração/rastreamento comercial. |
| Sugerir correção | Formulário e lista local de sugestões funcionam em memória; não chegam a uma fila editorial remota nem alteram catálogo. |
| Wrapped | Recorte fixo em setembro/2026; registros/horas/notas usam parte do diário real, mas comparação com agosto usa fórmula fixa, arquétipo “O Arquivista”/82% é fixo, e existem fallback de obra/nota/universo. Não é retrospectiva mensal/anual completa e confiável. A imagem de compartilhamento renderiza esses mesmos dados mistos. |
| Rankings e afinidade | Liga de previsões, precisão de teoristas e personas demo são fixos. A antiga lista “top loristas da semana” e notificações fictícias permanecem declaradas em `StaticContent`, mas **não são mais exibidas na central real**. Compatibilidade/progresso de perfis demo usa seed; perfis de pessoas reais omitem esses cartões. Não há algoritmo real de afinidade/ranking. |
| Badges de universo | No próprio perfil, o progresso é calculado localmente a partir do acervo/“visto”; badge é liberado pelo limiar de 50%. Não existe concessão/histórico de badge no servidor. Em personas demo, progresso pode ser calculado por seed. |
| Widgets | Ponte App Group e isolamento/limpeza por sessão estão implementados. Conteúdo é misto: progresso local/diário + ordem e duelo de amostra; delta do universo é fixo `3`. O widget não é prova de backend para duelo/ordens. |
| Live Activity | Extensão/layout, atributos e solicitação/atualização local via ActivityKit existem. Não há operação remota de estreia/APNs ActivityKit; tela de estreia continua simulada. |
| Capas/avatares | Cards usam composição gráfica/cores determinísticas e iniciais; não há upload de foto do usuário nem pipeline geral de pôsteres oficiais. Isso é apresentação implementada, mas não uma integração de mídia pronta. |

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
  comentários é respeitado pelos respectivos fluxos. O toggle global “Esconder spoilers”
  nos Ajustes é salvo, porém não é consultado pelas regras de renderização atuais.
- **Temas claro/escuro/sistema:** implementados com `UserDefaults`, não são falsos.
  Fonte, cores, animações, navegação e localização PT-BR/EN também são implementações reais.
- **Estatísticas Pro:** frequência/sequence, notas e registros derivam do diário;
  horas por universo usam duração estimada por tipo (`Logic.loreHours`), sem cronômetro.
- **StoreKit:** compra/restauração/entitlement verificado e tratamento de oferta existem.
  O esquema usa `Products.storekit` para testes. Sem Apple Developer/App Store Connect
  configurados e teste em dispositivo, não há venda de produção validada. O Pro não está
  vinculado ao UID Multiverse nem validado no backend; Wrapped anual prometido no material
  não é uma retrospectiva anual implementada.
- **Alterar senha nos Ajustes:** linha visual sem ação. Recuperação pela tela de login é
  um fluxo distinto, implementado; não confundir os dois.

## Preparado ou limitado por escopo, não “mock funcionando”

- **Push com app fechado:** código iOS/API e fila preparados; desativado por decisão do
  usuário, que ainda não tem Apple Developer. Faltam credencial APNs no Firebase,
  provisioning/build habilitado e validação de entrega em iPhone. Testes simulam FCM;
  não demonstram entrega real. [Passo a passo de ativação](../backend/api/docs/community-notifications.md).
- **Catálogo:** acervo inicial publicado é real, mas pequeno e incompleto. Home mostra
  seleção do catálogo, não ranking por tendência. O backend retorna `live=0`, sem presença.
  Star Wars/LoL/Tolkien em “em breve” não são catálogos completos prontos.
- **Marvel:** revisão/importação com Wikidata/TMDB existe; não significa catálogo completo
  nem atualização editorial automática. Metron continua aguardando credencial/cadastro.
- **Reviews de outras pessoas por obra/perfil:** o feed de seguidos e o detalhe funcionam;
  a seção de obra é rotulada “suas reviews”. Não há catálogo global de reviews de todos,
  nem página de histórico público completo no perfil remoto. Nenhuma amostra deve preencher
  esses estados vazios.
- **Comunidade nova:** texto/título, comentários e reações reais; não inclui mídia, edição
  de post publicado, reposts, busca textual, menções, respostas aninhadas, feed por ranking
  ou migração automática dos módulos antigos de teorias/duelos.
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

160 testes iOS; 72 unitários + 74 HTTP/PostgreSQL na API; PT/EN verificado (886 entradas).
Build opt-in de push compilado em simulador, sem envio real. O inventário é auditoria do
código; não afirma homologação em aparelho nem uso real de integrações ainda não ativadas.
