# Auditoria de código — 03/10/2026

Revisão dos fluxos ativos após mensagens privadas e ordens de leitura. Objetivo:
melhorar legibilidade e corrigir falhas comprovadas preservando contratos, layout,
localização PT-BR/EN e comportamento confirmado do produto.

## Escopo revisado

API: autenticação, banco/lifecycle, biblioteca/ordens, mensagens, relações sociais,
notificações, comunidade/salas/imagens/eventos, voz, atividade, catálogo e provedores.
iOS: stores correspondentes, cliente autenticado, sessão, widgets, compras, voz e push.
Firebase Functions: política de verificação, limites e vínculo da conta.
A revisão não constitui prova de ausência de bugs nem substitui QA em dispositivos.

## Correções e regressões

| Problema observado no código | Correção | Evidência automatizada |
| --- | --- | --- |
| Marcar mais de 100 alertas enviava apenas os primeiros 100, mas marcava todos localmente | Lotes de até 100 IDs únicos; atualização somente dos lotes confirmados | 120 alertas, duplicatas, falha no segundo lote e retry |
| Consulta antiga de preferências podia sobrescrever alteração confirmada | Revisão por operação e proteção durante salvamento | Resposta de consulta atrasada após salvar |
| Refresh automático reduzia mensagens e alertas às primeiras 30 entradas | Revalidar quantidade de páginas carregada e aplicar resultado completo atomicamente | 60 entradas, falha na segunda página, conversa removida e deduplicação |
| Erro antigo de histórico podia apagar conversa após envio confirmado | Validar versão de mutação também no caminho de erro | Resposta indisponível atrasada após envio |
| Novo cursor visível de DM era descartado enquanto leitura anterior estava pendente | Uma fila que agrega o maior cursor efetivamente visível, independente do cancelamento da tarefa da view | Dois cursores sobrepostos e cancelamento da tarefa anterior |
| Erro antigo de ordens podia substituir sucesso de seguir/votar | Validar revisão e identidade da consulta no caminho de erro | Consulta falha após follow confirmado |
| Encerramento da API podia instalar watchers tardios ou fechar listener duas vezes | Impedir watchers após shutdown, desvincular cliente antes de fechar e aguardar conexão pendente | Shutdown antes, durante e após conexão; sem listeners de abort remanescentes |
| Teste de limite de reações dependia de não atravessar a virada do minuto | Fixture com janela controlada e verificação explícita da expiração | Limite, retry idempotente e nova janela HTTP/PostgreSQL |

Limpeza adicional: formatação dos três stores alterados, remoção de unwraps
forçados desnecessários em ordens e duas advertências de lint nos testes API.
Não foram alteradas regras de produção de rate limit, contratos públicos ou views.

## Validação

- API: `npm run check` completo passou: formatação, lint, TypeScript, build,
  83 testes unitários e 130 HTTP/PostgreSQL. Após acrescentar mais uma regressão
  de shutdown durante conexão, os seis testes desse arquivo, lint e TypeScript
  passaram novamente: total atual de 84 testes unitários.
- iOS: `xcodebuild test`, iPhone 17 Pro / iOS 27 Simulator: 213 testes em 24 suites.
- Firebase Functions: 14 testes passaram.
- Localização: 1110 entradas PT-BR/EN validadas pelo script do projeto.
- PostgreSQL efêmero isolado para testes; nenhuma migration nova nesta auditoria.

## Limites e continuidade

QA manual de ordens/DMs em duas contas e voz em iPhones permanece com o usuário.
Push aguarda Apple Developer/APNs. Monetização continua documentada e adiada.
Não se transformaram recursos demo deliberadamente ocultos em funcionalidades reais.
Veja [inventário de demonstrações](DEMONSTRATION_INVENTORY.md).

Alterações locais preexistentes em `MockRepository.swift` e
`Localizable.xcstrings` ficaram fora do commit desta auditoria.


## Complemento — layout, fluidez e badge (03/10/2026)

- Nome de cadastro: sugestões normalizadas para handles válidos de até 24 caracteres;
  chips permanecem em uma linha rolável. Nomes longos não alargam o formulário.
  Scroll das telas permite dispensar o teclado interativamente.
- Boas-vindas mantém composição, cores e tamanhos; passa a rolar quando a altura
  não comporta todo o conteúdo. Tab bar mantém a fonte e pode contrair em 320 pt.
- Biblioteca/atividade usam pilhas lazy. Preparo de fotos (thumbnail/JPEG) agora
  executa em actor separado, com cancelamento antes/depois e limites preservados.
  Refresh da comunidade libera autores de páginas antigas e deduplica via Set.
- Badge local usa atividades não lidas do servidor (mensagens já estão incluídas),
  preserva o último total em falhas e limpa na troca/saída de conta. Escritas
  serializadas impedem resultado final de uma conta anterior. Permissão somente
  ao tocar Ajustes → Notificações → Contador no ícone do app; gestão posterior
  nos Ajustes do iOS. Não depende de APNs/Personal Team pago.
- Payload APNs preparado com o mesmo total visível do endpoint. Push permanece
  desabilitado: atualizar por novos eventos com app fechado exige Apple/APNs.

Validação: 229 testes iOS; 98 unitários API +135 HTTP/PostgreSQL. Teste temporário
UIHostingController renderizou cadastro com nomes longos, boas-vindas, tab bar,
Home/Busca, Biblioteca vazia/com 1.000 IDs, atividade e ajustes em PT-BR/EN;
320/390 pt e Biblioteca em 1024×768. Inspeção visual de cadastro, tab bar,
boas-vindas, ajustes e Biblioteca; estilos claro/noir preservados. Fixture de
1.000 linhas levou ~0,51 s incluindo espera deliberada de 350 ms e exportação PNG;
é diagnóstico no simulador, não benchmark de FPS/aparelho.

Limites: o harness confirmou foco nativo, mas o teclado do simulador reportou
frame fora da janela; não comprova a animação/posição do teclado no iPhone de
Rosa. Ainda validar essa percepção em aparelho, entrega APNs após configuração,
consumo de bateria/FPS em sessão prolongada e chamadas entre dois aparelhos.
Não foi reproduzido um travamento de cadastro. Threads de posts ainda recarregam
a primeira página de comentários após resposta; avatar por upload continua uma
pendência funcional anterior. Aviso de orientações do iPad não foi mascarado
com UIRequiresFullScreen. Não há promessa de ausência de todos os bugs.


## SOLID — responsabilidades e dependências (03/10/2026)

Pedido: aplicar SOLID onde houver necessidade, preservando o produto existente.
Revisados os pontos de composição iOS, stores, APIs, domínio dos avatares e os
serviços/controllers de comunidade. Refatoração orientada por acoplamentos
concretos, sem introduzir hierarquias ou interfaces sem consumidores.

- **Responsabilidade única:** `AccountAPIClient` adapta endpoints; o novo
  `AuthenticatedHTTPClient` cuida de sessão, token, retry único, cancelamento e
  decodificação HTTP. `MultiverseAPIErrorMapper` mantém os erros de domínio fora
  do transporte. No backend, `ClubsService`/`ClubsController` tratam clubes,
  agenda, membros e moderação; `RoomsService`/`RoomsController` tratam presença
  e assinaturas de mudanças. Clubes não recebem mais banco/eventos de salas.
- **Inversão de dependência e extensão:** o adaptador recebe
  `AuthenticatedRequesting`; o transporte aceita `APIErrorMapping`. É possível
  trocar o executor ou a política de erro sem editar os endpoints. As proteções
  de autenticação/cancelamento continuam pertencendo ao transporte.
- **Segregação e substituição:** `ClubsAPI` e `RoomsAPI` são contratos separados.
  Duelo, clubes, salas, voz e busca de pessoas são injetados explicitamente na
  composição em `RootView`; eliminados os casts que exigiam que a implementação
  de uma funcionalidade também implementasse outra, sem declarar esse requisito.
  Os testes usam implementações restritas de salas e duelos, sem AccountAPI ou
  CommunityAPI, e uma política de erro alternativa no transporte real.
- **Domínio independente da apresentação:** IDs de avatar em
  `Core/ProfileAvatarChoice.swift`; nomes localizados, UIImage/cache e recortes
  continuam no DesignSystem. Assets e renderização não mudaram.

Evidência: comparação do código antes/depois confirmou todos os corpos dos
métodos de salas, consultas SQL, rotas públicas e branches de erro de domínio
preservados (ignorando apenas espaço em branco). A suíte HTTP usa PostgreSQL e
cobre clubes/agendas/moderação, presença/atualizações, voz, bloqueios e exclusão.
A suíte iOS cobre sessão/troca de conta, retry, erros, stores e avatares; testes
adicionais verificam substituição por contratos menores e cancelamento que não
pode ser convertido em erro de domínio pela política injetada.

Nenhuma migração, mudança visual, mudança de tradução ou nova funcionalidade.
AppStore continua coordenando estado legado/demonstrações e navegação; esta
entrega não afirma que todos os tipos do projeto precisam de uma interface nem
que a arquitetura esteja definitivamente encerrada.
