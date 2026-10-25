# Auditoria white-box — Multiverse

Data: 22/10/2026. Base: `master`, commit `55e7bb303b4a7a04765796dec6ca23b924ac8cc3`.
Escopo: revisão de segurança do código e verificações locais. Não é certificação
de segurança nem pentest da infraestrutura publicada.

## Correções — 25/10/2026

WB-01 e WB-02 corrigidos e validados localmente. Migration 030 mantém recibos de
publicação independentes da review e reserva tentativas de foto antes de Sharp.
Cota de criação vale para diário privado e público; exclusão/limpeza não reembolsa,
retry de review existente não consome. Fotos: 20 tentativas/hora por UID, no máximo
uma por UID e duas por instância; perfil revalidado após processamento.

As sete regressões estão em `backend/api/test/white-box.e2e-spec.ts`, executadas
pelo CI regular e pelo atalho `audit:whitebox`. Incluem migração de consumo recente,
isolamento, concorrência, janela, imagens inválidas e exclusão durante processamento.
117 unitários + 174 HTTP aprovados. Publicação desta correção em andamento.
A descrição abaixo mantém as evidências da versão auditada em 22/10.

## Resultado

**Dois achados de prioridade P2 / gravidade média confirmados localmente.**
Ambos exigem uma identidade autenticada com e-mail verificado. Não foi demonstrado
acesso a dados de outra pessoa, execução de código ou tomada de conta.
Nenhuma falha crítica foi identificada nesta rodada; isso não comprova sua ausência.

| ID | Achado | Evidência | Estado |
| --- | --- | --- | --- |
| WB-01 | Exclusão de review devolve a cota horária de publicação | Após 20 publicações e um HTTP 429, excluir uma permitiu outra com HTTP 200 | Corrigido e validado localmente em 25/10 |
| WB-02 | Imagem de perfil processada antes da autorização do perfil, sem cota própria de processamento | Uma conta sem perfil recebeu 404, mas o encoder Sharp já havia sido chamado | Corrigido e validado localmente em 25/10 |

Recomendação: tratar WB-01 e WB-02 no próximo lote local, antes de ampliar o beta.
As recomendações de capacidade e pendências operacionais abaixo permanecem
separadas dos achados reproduzidos.

## WB-01 — Exclusão permite contornar a cota de publicações

**Local:** [ActivityService](../backend/api/src/activity/activity.service.ts),
linhas 78–88 (contagem), 115–120 (remoção da review ao limpar nota/texto) e
138–163 (exclusão do registro). Rota reproduzida: `PUT /api/v1/me/diary/:id`,
com `DELETE /api/v1/me/diary/:id` entre as publicações.

**Causa:** o limite de 20 novas reviews públicas por hora conta apenas as linhas
que ainda existem em `reviews`. A exclusão do registro remove a review e reduz
essa contagem. O marcador de exclusão impede reutilizar o mesmo UUID, mas não
impede publicar com um UUID novo.

**Reprodução local:**

1. Criar uma conta de teste com perfil, onboarding concluído e diário público.
2. Publicar 20 reviews com UUIDs diferentes; todas retornam 200.
3. Tentar outra publicação; recebe 429, confirmando que a cota está esgotada.
4. Excluir um dos registros; recebe 200.
5. Publicar com um novo UUID na mesma hora; recebe **200**, quando deveria
   continuar recebendo **429**.

**Impacto:** permite repetir ciclos de publicação/exclusão, contornando o controle
contra spam e gerando trabalho no banco e no feed. Não permite excluir registros
de terceiros. O teste fez apenas um ciclo após atingir a cota, sem teste de carga.

**Correção proposta:** usar contador ou registro de consumo por UID/janela,
independente da existência da review, atualizado atomicamente no fluxo de
`AccountLifecycleService`. Preservar a idempotência: repetir uma publicação já
confirmada não deve consumir outra unidade. Remover texto/nota, excluir o diário
ou alternar a privacidade não deve reembolsar uma publicação já consumida.
Definir explicitamente a política de republicação ao tornar um diário público;
a alternância de privacidade não foi reproduzida nesta rodada.

**Aceite:** o passo 5 retorna 429; retries legítimos continuam funcionando;
nova janela libera a cota; concorrência, edição e exclusão não a reiniciam.
Promover o teste da auditoria para a suíte regular após corrigir.

## WB-02 — Trabalho de imagem antes de autorizar o perfil

**Local:** [ProfileEditorService](../backend/api/src/accounts/profile-editor.service.ts),
linhas 19–55. Rota: `PUT /api/v1/me/profile/details`.

**Causa:** o serviço decodifica a imagem, lê metadados, redimensiona e produz JPEG
antes de entrar em `withActiveAccount` e verificar a existência do perfil. A rota
não tem cota de tentativas/processamentos por usuário. O lock de ciclo de vida
também só é adquirido depois desse trabalho. Há limites por imagem — corpo,
20 milhões de pixels e saída de 256 KiB —, mas não de repetição dessas operações.

**Reprodução local:** um UID verificado fictício, sem linha em `profiles`, envia
um PNG válido de 8×8 pixels. A resposta é corretamente 404 `PROFILE_REQUIRED`,
porém um spy com execução real em `sharp.prototype.toBuffer` registra **uma
chamada**. O controle esperado é zero chamadas ao encoder para esse perfil.
Foi usada uma imagem minúscula; não houve saturação nem medição de indisponibilidade.

**Impacto:** usuários autenticados, inclusive sem perfil, podem provocar trabalho
de mídia que será descartado. Repetição/concorrência pode consumir CPU e memória
do processo compartilhado e aumentar custos de execução. O teste confirma a
ordem indevida, não quantifica a carga necessária para degradar o serviço.

**Correção proposta:** validar conta/perfil e reservar uma cota durável antes do
processamento; limitar também concorrência de decodificação e considerar tentativas
inválidas no orçamento. Revalidar a conta antes de persistir, para não reintroduzir
dados após exclusão concorrente. Manter limites de bytes/pixels, formatos aceitos,
re-encoding e descarte de metadados. Reaproveitar os padrões existentes de quotas
e ciclo de vida; não exige provedor novo nem serviço pago.

**Aceite:** conta sem perfil ou em exclusão não aciona o encoder; excesso recebe
429 antes de processar; substituição legítima continua funcionando; concorrência
e exclusão de conta não deixam imagens órfãs ou restauram dados apagados.

## Melhorias preventivas e pendências já conhecidas

Estas observações não foram classificadas como novos exploits comprovados:

- **E06 — Limites gerais e long polling:** não foi encontrado limitador global
  na composição da API. `RoomEventsService.watch` mantém listeners/timers por
  requisição por até 20 segundos sem teto explícito por UID/instância. Há limpeza
  por abort/timeout e uma conexão compartilhada de LISTEN. Definir orçamento de
  requisições/conexões e confirmar as proteções de borda antes de concluir sobre
  a exposição real. Não foi realizado teste de carga ou DDoS.
- **E03 — Paginação:** `ActivityService.snapshot` retorna todo o diário e suas
  reviews; cada escrita também devolve o snapshot. Logs sem texto/nota não passam
  pela cota de publicação pública. Planejar paginação e orçamento de mutações para
  que históricos grandes não ampliem indefinidamente consulta, resposta e memória.
- **Rotação Resend:** `backend/firebase/PENDING_SETUP.md:9` registra uma chave
  anteriormente compartilhada no chat e solicita rotação. A validade atual e a
  conclusão dessa rotação não foram verificadas; não é evidência de chave exposta
  atualmente no Git. Confirmar a resolução antes do lançamento, sem divulgar a chave.
- **Operação:** homologação integrada, regras reais dos provedores, backups,
  restauração e retenção continuam pendentes conforme L06/L10. Não confundir
  `maxInstances`, quotas por usuário ou alertas financeiros com teto de gasto.

## Escopo e controles examinados

| Área | Evidência desta rodada | Limite da conclusão |
| --- | --- | --- |
| Autenticação Nest/Firebase | Guard global; verificação Admin com revogação; rejeição de anônimo/e-mail não verificado; UID derivado do token | Nos testes HTTP o verificador é substituído por identidades fictícias; não testa assinatura real nem login no provedor |
| Autorização e isolamento | Revisão de consultas por UID, lifecycle, biblioteca, diário, mensagens, bloqueios, imagens e políticas sociais; testes existentes reexecutados | Cobertura finita; não prova todas as combinações de corrida/permissão |
| Entrada e SQL | DTOs, allowlists, limites de payload, parâmetros SQL e cursores nos caminhos revisados | Não foi usado fuzzer exaustivo de todos os endpoints |
| Código por e-mail | Revisão dos handlers, HMAC, expiração, tentativas, reenvio, geração e App Check; 14 testes locais | Sem envio real, acesso ao Firestore de produção ou teste real de App Check |
| Ambientes/operação | Validação de ambiente/projeto/identidade do banco; CI com permissão de leitura e actions por SHA; readiness | Não audita IAM, console, configuração atual de borda ou prova deploy bem-sucedido |
| Cliente iOS | Leitura de cliente autenticado, geração de sessão, links de recuperação e limpeza de push | Sem nova execução do simulador, captura de tráfego, inspeção de binário ou teste em aparelho |
| Dependências Node | `npm audit --omit=dev --json` na API e nas Functions | Zero advisories retornados em ambos; não cobre dependências de desenvolvimento, Swift, imagens Docker ou falhas ainda não publicadas |
| Segredos no checkout | Busca de padrões de private keys, tokens GitHub/AWS/OpenAI/Resend em 479 arquivos de texto rastreados, até 3 MB | Nenhuma correspondência; não é análise de histórico Git, arquivos ignorados, logs ou detector universal de segredos |

## Execução reproduzível

A suíte de auditoria está em
[white-box.audit.ts](../backend/api/test/white-box.e2e-spec.ts), separada dos testes
regulares para manter os achados explícitos. Ela contém as **asserções desejadas**,
sem inverter os resultados para fazer falhas de segurança parecerem aprovadas.

Na pasta `backend/api`, com Docker local ativo:

```sh
bash scripts/with-test-db.sh audit:whitebox
```

O wrapper cria PostgreSQL 18 em loopback, com porta aleatória, credenciais
descartáveis e remoção ao terminar. A API usa schema próprio, servidor local,
verificador Firebase fictício, voz/push desativados e nenhum envio de e-mail.
Não configurar esse comando com banco ou credenciais de produção.

Resultado em 22/10/2026: **exit 1**, 3 testes, **1 aprovado e 2 falhando**:

```text
CONTROL: sem autenticação e exclusão por outra conta — aprovado
WB-01: expected 200 to be 429
WB-02: expected toBuffer to not be called; called 1 time
```

O teste de controle confirma 401 sem autenticação, 404 ao excluir o diário de
outra conta e permanência do registro original no banco.

Validação regular reexecutada: `npm run check:local` **exit 0**, format/lint/tipos/
build e **117 testes unitários + 167 HTTP/PostgreSQL** aprovados. Functions:
`npm test` **exit 0**, **14 testes** aprovados. Isso mostra que os dois cenários
adversariais não eram cobertos pelas asserções anteriores; não invalida seus
resultados nem equivale a aprovação de segurança global.

Logs locais: `/tmp/multiverse-whitebox-probes.log`,
`/tmp/multiverse-whitebox-baseline.log`,
`/tmp/multiverse-whitebox-functions-tests.log`. Os resultados essenciais estão
transcritos acima; arquivos em `/tmp` são temporários.

## Entrega e próximos passos

- [x] Revisão e reproduções locais concluídas; achados incluídos no plano.
- [x] Diagnósticos preservados para repetir após a correção.
- [ ] Corrigir WB-01 com quota independente da existência do conteúdo.
- [ ] Corrigir WB-02 com autorização, quota e limite de concorrência antes da mídia.
- [ ] Converter os testes corrigidos em regressões regulares e repetir a auditoria.
- [ ] Confirmar rotação Resend e concluir pendências operacionais autorizadas.

Nenhum código de execução da aplicação foi alterado nesta rodada. As alterações
são de documentação e ferramentas de diagnóstico local. Não houve push/deploy,
teste contra produção, ativação de faturamento ou criação de serviço pago.
As alterações locais preexistentes de MockRepository e do vídeo de marketing
foram preservadas.
