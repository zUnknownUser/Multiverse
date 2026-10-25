# Operação da API

Contrato do lote local L10. Nenhum serviço pago, monitor externo ou deploy é
necessário para executar os testes. A validação integrada de homologação foi
adiada por Lucas em 21/10/2026.

## Liveness e readiness

As duas rotas são públicas e retornam `Cache-Control: no-store`, além dos headers
de segurança e `X-Multiverse-Environment` existentes.

| Rota                       | Sucesso                                                      | Indisponibilidade                                                  | Uso                                                                                     |
| -------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| `GET /api/v1/health`       | 200, `{status:"ok",service:"multiverse-api",environment}`    | Não consulta dependências                                          | Processo responde; contrato existente preservado                                        |
| `GET /api/v1/health/ready` | 200, `{status:"ready",service:"multiverse-api",environment}` | 503, `{status:"unavailable",service:"multiverse-api",environment}` | PostgreSQL responde pelo pool da aplicação e sua identidade coincide com a configuração |

Readiness recusa banco ausente, inacessível ou com identidade ausente/divergente.
A consulta é somente leitura, tem timeout e não chama Firebase, Resend, LiveKit
ou OpenAI. O resultado fica em memória por até 5 segundos; requisições concorrentes
compartilham a mesma verificação. A resposta espera no máximo 2 segundos pelo
probe, sem expor URL, SQL, credenciais ou detalhes do erro. Uma consulta já iniciada
é encerrada pelo timeout do driver; uma nova não começa enquanto ela estiver ativa.

Uma resposta pronta não comprova disponibilidade dos provedores externos, schema
completo, entrega de e-mail ou execução dos workers. Liveness não deve reiniciar o
processo apenas porque o banco está indisponível. Em uma publicação futura, usar
`/api/v1/health/ready` como gate de prontidão. A configuração remota do Railway
continua inalterada; seu healthcheck de deploy não substitui monitoramento contínuo.

## Diagnóstico privado dos processos automáticos

Depois de `npm run build`, executar `npm run ops:report` com
`OPERATIONS_DATABASE_URL`, `APP_ENV` e `FIREBASE_PROJECT_ID` explícitos no ambiente.
O comando não carrega `.env` e não usa `DATABASE_URL` como fallback. Usar uma
conexão autorizada e preferencialmente um usuário PostgreSQL somente leitura.
Nunca colocar credenciais no Git, no histórico de comandos ou na saída do relatório.

O relatório verifica a identidade do banco antes de consultar as filas e lê tudo
em uma transação somente leitura com snapshot consistente. A saída JSON contém
apenas ambiente, horário, totais e idades em segundos:

- Exclusões de conta: pendentes, já tentadas, pendentes há mais de 15 minutos e
  idade da mais antiga. Uma tentativa anterior não comprova falha do Firebase.
- Push: pendentes, vencidas para processamento, com tentativas anteriores,
  vencidas há mais de 15 minutos e idade do agendamento vencido mais antigo.
  Push desligado pode acumular pendências; isso não comprova erro de envio.
- Voz: sessões expiradas ou revogadas e quantas estão assim há mais de 5 minutos.
  Não é a lista completa de remoções por perda de permissão/bloqueios entre usuários.

`attentionRequired` sinaliza pelo menos uma pendência acima desses limites de
triagem. Eles orientam investigação, não são SLA nem prova de que o worker parou.
Saída 0: consulta concluída sem pendência antiga; 2: consulta concluída com atenção
necessária; 1: configuração inválida, identidade incorreta ou consulta indisponível.
Erro sempre usa código genérico, sem conteúdo do banco ou resposta do provedor.

O comando não envia mensagens, não reprocessa trabalhos, não altera dados e não
publica métricas na internet. Conferir flags/configuração e disponibilidade dos
provedores antes de intervir; não apagar exclusões pendentes nem marcar push como
enviado manualmente. Não há agendamento/alerta automático configurado neste lote.

## Pendências de operação

Monitoramento hospedado, alertas com destinatários definidos, retenção de logs,
backups/restauração e validação dos workers com provedores reais continuam em L10.
Não contratar ou ativar recursos pagos sem teto aprovado; alertas de orçamento
não equivalem a bloqueio financeiro. Ver [ambientes](../../../docs/ENVIRONMENTS.md).

## Ensaio local de recuperação

`npm run test:recovery:local` cria um PostgreSQL 18 descartável em loopback, aplica
todas as migrations, insere perfil/diário/review/cotas sintéticos, faz `pg_dump -Fc`
e restaura em outro banco com `pg_restore --exit-on-error`. Compara SHA-256 das
linhas de todas as tabelas, repete o migrador e valida cascatas e cotas. Exige
container criado pelo wrapper, label de teste, porta correspondente e auto-remove;
recusa URLs remotas. Dump só em memória; container/bancos removidos ao sair.
Validação em 25/10/2026: 70 tabelas restauradas com sucesso. Não é backup de produção.

Produção ainda requer retenção e destino protegido aprovados, backup automatizado
e ensaio com uma cópia real isolada. Não ativar PITR ou armazenamento pago sem
orçamento. Ao operar backup real: usar credencial de leitura apropriada, cliente
PostgreSQL compatível, destino cifrado e sem versionar o dump; restaurar somente
em banco novo/isolado, verificar contagens/checksums e identidade do ambiente,
e nunca conectar o app HML à cópia identificada como produção. Registrar data,
duração, versão e resultado sem conteúdo/segredos; apagar a cópia de ensaio após
conferência. A restauração não pode ser tratada como homologada só pelo ensaio sintético.

Railway em 25/10: compute hard US$10/ciclo e soft US$5; Agent hard US$0.
Os menores valores permitidos foram aplicados e relidos via `railway usage limit
status --json`. Hard de compute zero desabilitaria o teto, portanto não usar.
Ao atingir o teto o Railway interrompe os workloads; observar disponibilidade e
consumo no ciclo seguinte. Não equivale a teto global da fatura ou dos outros
provedores. Nenhum plano/serviço novo habilitado.
