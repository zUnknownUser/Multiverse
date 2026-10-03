# Voz nas salas — primeira versão

Integração LiveKit Cloud nativa (Swift SDK 2.17.0), só áudio. O chat persistido e seu
canal de atualizações continuam independentes. Conexão de mídia criada somente ao
entrar; a sheet pode ser recolhida mantendo voz e conversa na mesma tela.

## Experiência

- Botão discreto VOZ na sala, painel no design system PT-BR/EN, até oito pessoas.
- Entrada para ouvir, sem captura de microfone. FALAR solicita permissão apenas no
  primeiro uso; recusar preserva a escuta. SILENCIAR e saída de áudio/fones no painel.
- Participantes e indicação de fala vêm de eventos do SDK, sem consulta periódica
  de participantes nem atualização de interface a cada amostra de áudio.
- Sair da voz desconecta a mídia imediatamente. Sair da tela, trocar o trecho ou
  colocar o app em segundo plano encerra a voz. Recolher o painel mantém a conexão.
- Não há vídeo, gravação, anfitrião/palco, pedir fala ou moderação ao vivo nesta etapa.
  Bloqueios existentes são respeitados na entrada e na revalidação das sessões.

## Contrato e autorização

Todos os endpoints exigem Firebase verificado. A entrada exige onboarding, conta
ativa, obra publicada e progresso suficiente para o trecho (0/50/100).

- `GET /community/voice`: `{enabled,maxParticipants}`.
- `PUT /community/rooms/:item/voice/:uuid`: `{segment:0|1|2}`; UUID estável por tentativa,
  retorna `{id,room,serverURL,token}`. Identidade de mídia é UUID opaco; nome vem do
  perfil. Uma sessão ativa por conta, oito por sala/trecho, trinta novas entradas/hora.
- `PUT /community/voice/:uuid/heartbeat`: renova autorização/lease, `{active:true}`.
- `DELETE /community/voice/:uuid`: revoga a própria sessão; `{left:true}` idempotente.

Tokens de 60s permitem apenas fonte microphone. Camera, screen share, data, gravação,
administração e alteração de metadados não são concedidos. Segredos ficam no servidor.
Tokens não são autorização permanente: o iOS renova a lease a cada 20s; ausência de
renovação expira em 60s. Worker de 15s remove sessões expiradas ou que perderam acesso
(progresso, catálogo, conta ou bloqueios). Uma consulta seleciona apenas sessões
inválidas; operações remotas em lotes de oito, até 200 por rodada. Revogações podem
levar até uma rodada; indisponibilidade do provedor pode adiar a remoção no servidor.
A desconexão local não espera essa limpeza.

Migration `018_room_voice.sql` retém a identidade de sessões revogadas por dois
minutos, além da duração do token, para retirar entradas atrasadas. Não há FK da
lease para perfil/obra: após uma exclusão, a limpeza ainda precisa desconectar a
identidade de mídia. O registro de limite por conta tem FK com exclusão em cascata.
LiveKit Cloud é obrigatório nesta versão para a revogação dos tokens no provedor.
Desligar VOICE_ENABLED impede entradas e faz o worker encerrar sessões remanescentes.

## Configuração

No `.env` ignorado e nas variáveis secretas do serviço `api` no Railway:

```
VOICE_ENABLED=true
LIVEKIT_URL=wss://<projeto>.livekit.cloud
LIVEKIT_API_KEY=<chave>
LIVEKIT_API_SECRET=<segredo>
```

As quatro variáveis foram configuradas no projeto autorizado. Nunca copiar segredo
para o app, documentação ou logs. Rotação: substituir chave/segredo no `.env` e no
Railway e redeployar a API. Push/APNs continuam desativados; não são usados aqui.

## Verificação

- 81 testes unitários API, 106 HTTP/PostgreSQL, 184 iOS; catálogo com 1060 entradas.
- JWT de teste verificado: microfone apenas, sem grants de vídeo/dados/admin/gravação.
- HTTP: progresso/trechos, idempotência, outro usuário, capacidade, bloqueios,
  expiração, conta apagada, limite de entradas e desligamento do recurso.
- iOS: entrada sem publicar, ação explícita do microfone, permissão negada e
  cancelamento antes do token chegar. Compilação Swift 6 e suite completa aprovadas.
- Dois clientes WebRTC reais conectaram ao projeto autorizado e transmitiram áudio
  sintético usando a fonte microphone. Sala de verificação removida ao concluir.
- Validação de microfone físico, Bluetooth e interrupções de chamadas no iPhone
  ainda requer teste em dispositivos. Não confundir o teste de transporte com essa QA.

Fontes: [Swift SDK](https://github.com/livekit/client-sdk-swift),
[grants](https://docs.livekit.io/frontends/reference/tokens-grants/).
