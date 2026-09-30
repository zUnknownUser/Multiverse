# Autenticação por e-mail — preparada, não publicada

O app mantém o fluxo do protótipo: cadastro → código de seis dígitos → nome/apelido →
avatar/bio. Recuperação: e-mail → link → tela Nova senha. Nenhum serviço foi publicado
por esta implementação e nenhum e-mail real foi enviado nos testes.

## O que está implementado

- Firebase Authentication cria a conta com e-mail/senha, inicialmente não verificada.
- O app chama `requestEmailVerificationCode` autenticado com o UID da conta recém-criada.
- A função consulta o e-mail no Firebase Auth; não aceita destinatário arbitrário do app.
- Código aleatório de seis dígitos, validade de 10 minutos, cinco tentativas por código,
  intervalo de 60 segundos e no máximo cinco envios por hora por UID.
- Um reenvio substitui o código anterior. Firestore armazena somente o HMAC do código.
- `confirmEmailVerificationCode` registra tentativas em transação e usa Admin SDK para
  marcar `emailVerified`. O app recarrega o usuário e atualiza o token antes de avançar.
- As duas funções exigem Firebase Authentication e App Check.
- O transporte de e-mail preparado é Resend, isolado na função de envio. Pode ser
  substituído por outro provedor antes da ativação; não existe chave de envio no app.
- A recuperação usa `sendPasswordReset` do Firebase, com links móveis. O app valida
  domínio, projeto, modo e código antes de apresentar a tela Nova senha. A senha só
  muda com `confirmPasswordReset`; depois tenta entrar com as novas credenciais.
- Caso o login após redefinir falhe, o usuário volta ao login sem reutilizar o código.

O nome de exibição fica no Firebase Auth. Apelido, cor e bio ainda são locais por UID.
O selo de formato válido não significa reserva global do apelido. Login por @usuário,
perfis públicos e unicidade exigirão o backend de perfis na próxima etapa.

## Ativação futura

1. Habilitar **E-mail/senha** em Firebase Authentication. Apple continua pendente.
2. Habilitar Firestore e um plano Firebase compatível com Cloud Functions. Não foi feita
   alteração de plano nem contratação de serviço nesta tarefa.
3. Configurar um domínio remetente no provedor de e-mail. A configuração preparada usa
   `RESEND_API_KEY` e `VERIFICATION_EMAIL_FROM` (por exemplo, `Multiverse <conta@seu-dominio>`).
4. Em `firebase/`, configurar os segredos pelo Secret Manager, nunca pelo app ou Git:
   `firebase functions:secrets:set RESEND_API_KEY` e
   `firebase functions:secrets:set VERIFICATION_CODE_SECRET`.
   O segundo deve ser um segredo aleatório forte, com pelo menos 32 bytes de entropia.
   `VERIFICATION_EMAIL_FROM` será solicitado no deploy ou pode ficar no arquivo local
   ignorado `functions/.env.multiverse-7f87c`.
5. Registrar o app no **App Check** com App Attest. Em Debug/simulador, registrar no
   console o token do provedor de debug exibido pelo SDK no Xcode. Tratar esse token
   como segredo; não incluí-lo em commits ou capturas públicas. Release usa App Attest.
6. Registrar Team ID `5RS2AA677K` e Bundle ID `com.nexussoft.multiverse` no app Apple do
   Firebase e configurar Hosting para os links. `hosting/.well-known/apple-app-site-association`
   está preparado com essa associação. O app já declara o domínio
   `applinks:multiverse-7f87c.firebaseapp.com`.
7. Conferir o domínio autorizado no Authentication e os modelos de e-mail de recuperação.
   Usar os links do Firebase Hosting atual, sem Firebase Dynamic Links.
8. Depois de revisar a configuração, publicar as funções, regras e associação com
   `firebase deploy --only functions:multiverse-auth,firestore:rules,hosting`.
   As regras fornecidas negam acesso direto ao banco: integrar com outras regras caso
   o projeto passe a ter coleções acessíveis pelo app antes desse deploy.
9. Configurar TTL no campo `purgeAt` da coleção `emailVerificationChallenges` para
   limpeza automática. A expiração do código é validada no servidor mesmo sem TTL.

O endpoint de associação retornava 404 durante a implementação; por isso a abertura
real dos links no app ainda depende da etapa de Hosting. No dispositivo, validar o link
com o app instalado e a assinatura contendo Associated Domains. Se o app não abrir,
o handler web do Firebase poderá apresentar a recuperação no navegador.

## Validação local

```sh
cd functions
npm ci
npm test
```

Os testes verificam as políticas de código sem enviar e-mails nem acessar o projeto
real. O app também tem testes de autenticação, erros, sessões, reenvio e validação de
links com clientes injetados. Entrega de e-mail, App Check, transações no Firestore e
abertura de links em aparelho precisam de teste integrado após a configuração externa.

Referências: [callables](https://firebase.google.com/docs/functions/callable),
[ações de e-mail](https://firebase.google.com/docs/auth/ios/passing-state-in-email-actions),
[App Check](https://firebase.google.com/docs/app-check/cloud-functions).
