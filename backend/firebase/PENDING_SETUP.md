# Retomar envio de códigos por e-mail

Atualizado em 01/10/2026, a pedido do usuário.

- Domínio `somosmultiverse.com.br` pago e publicado. Em 01/10/2026, os dois servidores DNS autoritativos confirmaram CNAME rsend -> rsend-sae1.forge.rmta.net, CNAME send -> send.forge.rmta.net e TXT resend._domainkey com a chave fornecida. Usuário informou conclusão da verificação no Resend.
- Remetente publicado: `Multiverse <elesys@somosmultiverse.com.br>`.
- Não alterar `vendlydigital.com.br`, usado por outra aplicação.
- DNS concluído; verificação no Resend informada como concluída pelo usuário. Em 01/10/2026, projeto vinculado à conta ativa Pagamento do Firebase (final 722767); API Google Cloud confirmou billingEnabled=true. Blaze habilitado. Orçamento mensal de R$ 50 criado e confirmado via API, restrito ao projeto Multiverse (542469411124), com alertas de gastos reais em 50%, 90% e 100% e destinatários padrão de faturamento. ID do orçamento: 175ac460-607e-4604-803d-7786815abb63. É um alerta, não um bloqueio automático de gastos.
- A chave Resend fornecida tem permissão apenas para envio, sem acesso à gestão de domínios. Foi compartilhada no chat e deve ser rotacionada; não armazenar chaves neste arquivo nem no Git.
- RESEND_API_KEY e VERIFICATION_CODE_SECRET cadastrados no Secret Manager; as duas Cloud Functions estão ACTIVE com o remetente elesys e o template HTML PT-BR/EN.
- Firestore (default) criado em us-central1 com proteção contra exclusão, regras fechadas e TTL purgeAt ACTIVE. App Attest consultado; Team ID configurado no app Firebase. Hosting e associação Apple publicados (HTTP 200).
- 11 testes locais passaram, build iOS passou e as duas funções rejeitam chamadas anônimas (401). Prévia HTML enviada ao e-mail autorizado, aceita pelo Resend. Falta confirmação de recebimento pelo usuário e teste completo de cadastro/confirmação/reenvio no app.
- O fluxo de seis dígitos confirma o cadastro. Recuperação de senha continua por link; associação Hosting publicada, abertura em aparelho físico ainda deve ser validada.
- Em 02/10/2026, o usuário pediu a retomada geral do app e a conclusão das interações sociais. Esta nota continua registrando somente pendências da autenticação; o estado consolidado está em `../../docs/SESSION_HANDOFF.md`.
- API e PostgreSQL provisionados no Railway (projeto `multiverse`). URL: `https://api-production-6e8d.up.railway.app/api/v1`. Credencial Firebase Admin fornecida pelo usuário cadastrada na variável privada FIREBASE_SERVICE_ACCOUNT_JSON. Isso é independente da ativação das Cloud Functions para envio de códigos.

- Simulador iPhone 17 Pro de Lucas registrado no App Check em 01/10/2026, sem versionar o token. Outros aparelhos Debug precisam do próprio registro.
