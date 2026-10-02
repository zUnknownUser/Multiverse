# Pessoas e relações

Todas as rotas abaixo usam o prefixo `/api/v1`, identidade Firebase verificada e
perfil ativo com onboarding concluído. Nenhuma chave de provedor vai para o app.

| Rota                                                      | Resultado                                                             |
| --------------------------------------------------------- | --------------------------------------------------------------------- |
| `GET /people?q=alice&limit=20&after=alice`                | Busca por nome ou @usuário, ignorando caixa/acentos; cursor opcional. |
| `GET /people/suggestions`                                 | Pessoas ainda não seguidas, excluindo a própria conta.                |
| `GET /people/:id`                                         | Perfil público resumido e contadores reais.                           |
| `PUT /me/follows/:id` com `{"following":true}` ou `false` | Define a relação e devolve o estado confirmado.                       |

Busca e sugestões retornam `{users,nextCursor,state}`. Perfil e alteração retornam
`{person,state}`. `state` contém `version`, `followingIDs` e `followerCount` da
conta autenticada. Perfis expõem somente ID, @usuário, nome, cor do avatar, bio e
contagens de registros/seguidores/seguidos; não expõem e-mail, texto do diário ou
credenciais. Contas incompletas ou em exclusão não entram na descoberta.

O limite padrão é 20, máximo 50, com cursor por @usuário e ordenação estável.
`q` aceita até 80 caracteres; busca vazia lista pessoas elegíveis. Não há total
global de resultados; o app usa “Resultados” e “Ver mais”. Nome/bio escritos por
usuários são preservados, enquanto estados e ações têm PT-BR e inglês.

Seguir é idempotente: repetir o mesmo estado não duplica relações nem aumenta
contadores. A transação usa a relação `follows` existente e avança a versão do
onboarding apenas se houver mudança. Gravações antigas de onboarding concluído
preservam essas relações canônicas, sem voltar a exigir três pessoas. Exclusão
de conta usa o ciclo de vida já existente. Não é necessária migration nova.

## iOS e falhas

`PeopleAPI`/`PeopleStore` separam descoberta/relações do catálogo e diário.
`AccountAPIClient` reutiliza a autenticação, limita a renovação do token e impede
uma requisição de outra conta após troca de sessão. As telas existentes mantêm
seus componentes, cores e tipografia. A busca espera 250 ms após digitação;
resultados antigos são descartados e páginas repetidas não duplicam linhas.

Seguir/deixar de seguir aguarda confirmação, bloqueia envios simultâneos e
preserva o estado anterior em erro. Consultas atrasadas não desfazem uma relação
já confirmada. Home e perfil aceitam puxar para atualizar. Perfil removido tem
mensagem própria; consulta vazia é informativa, e falha de rede oferece retry.

Perfis reais mostram apenas métricas comprovadas. Afinidade, selos e histórico
público ainda não disponíveis não recebem números de demonstração. Mensagens e
desafios conservam os controles existentes com aviso de disponibilidade futura.
O [feed social](social-feed.md) mostra as reviews públicas das pessoas seguidas,
além das próprias. Bloqueios recíprocos também filtram descoberta, perfis,
contadores e sugestões do onboarding.

## Validação

Testes HTTP com schema PostgreSQL isolado cobrem autenticação, busca, paginação,
campos públicos, exclusão, idempotência, concorrência, rollback e compatibilidade
com onboarding antigo. Testes iOS cobrem erro/retry, conta isolada, restauração,
respostas fora de ordem, confirmação, tradução e transporte autenticado.

Para testar com duas contas: concluir os dois cadastros, localizar a outra conta
em Busca → Pessoas, abrir o perfil, seguir, reabrir o app e deixar de seguir.
Conferir os contadores nas duas contas após atualizar. Sem internet, a ação
deve explicar a falha sem anunciar sucesso; reconectar e repetir. Conferir em
inglês e português. Sem outras contas elegíveis, a Home não mostra sugestões.

Comentários e reações persistidos, permissões e operação de moderação estão
documentados em [interactions.md](interactions.md).
