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
