# Biblioteca privada

`GET /api/v1/me/library` e `PUT /api/v1/me/library` exigem token Firebase,
e-mail verificado e onboarding concluído. O UID vem da autenticação; não há rota
para consultar listas, desejos ou favoritos de outra conta.

GET retorna `version`, `wantedIDs`, `favoriteIDs` e `lists`. Cada lista contém
`id`, `title`, `description`, `itemIDs`, `createdAt` e `updatedAt` (datas ISO8601).
O estado inicial é vazio, versão zero, exceto pelos favoritos migrados do diário.

PUT exige `mutationID` UUID v4, `version` obtida no GET e uma ação:

| action                    | Campos adicionais obrigatórios                        |
| ------------------------- | ----------------------------------------------------- |
| wanted / favorite         | itemID, enabled (boolean)                             |
| create_list / update_list | listID (UUID v4), title, description (pode ser vazia) |
| delete_list               | listID                                                |
| add_item / remove_item    | listID, itemID                                        |

Campos desconhecidos, nulos ou fora da ação são rejeitados. Título: não vazio,
até 100 caracteres; descrição: até 1.000. São permitidas 50 listas por conta,
200 obras por lista e 1.000 obras distintas marcadas entre desejos/favoritos.
Limite de 120 alterações confirmadas por minuto por conta. Inserções exigem obra
publicada em universo ativo; a remoção de obras arquivadas continua possível.
Adicionar a mesma obra à lista não duplica a associação. Excluir lista não altera
diário, desejos ou favoritos. As listas são ordenadas pela criação mais recente;
itens seguem a data de inclusão, sem reordenação manual nesta etapa.

## Concorrência e retry

Cada alteração usa transação e o mesmo bloqueio de conta dos fluxos de exclusão.
Versão antiga retorna 409 `LIBRARY_STALE`, sem sobrescrever outro dispositivo.
Sucesso retorna `{mutationID, appliedVersion, state}`. Um retry com o mesmo UUID e
corpo devolve o recibo original e o estado **atual**, mesmo após outra alteração ou
exclusão da lista. Não repete a escrita nem consome nova quota. Reusar o UUID com
outro corpo retorna 409 `LIBRARY_MUTATION_CONFLICT`.

Demais erros: 404 `LIST_UNAVAILABLE`/`ITEM_UNAVAILABLE`, 409 `LIBRARY_LIST_CONFLICT`,
`LIBRARY_LISTS_LIMIT`, `LIST_ITEMS_LIMIT`, `LIBRARY_ITEMS_LIMIT`, 429
`LIBRARY_RATE_LIMIT` e 400 `INVALID_LIBRARY_REQUEST`.

O iOS só altera o estado após confirmação, mantém UUID/corpo quando a resposta é
incerta e permite tentar de novo. Conflito atualiza os dados e exige nova ação do
usuário. O pending vive na sessão; não existe fila de escrita offline persistente
após encerrar o app. Ao reabrir a biblioteca, o app carrega o estado confirmado.
Não há sincronização push: leitura ao abrir, retornar ao app e puxar para atualizar.

## Migração e escopo

`013_personal_library.sql` importa uma vez o favorito do registro mais recente de
cada obra no diário (`logged_at`, desempate `id`). Novas marcações de favorito na
biblioteca são independentes de `liked` no diário. Listas e desejos do protótipo
eram memória local e não são importados. Todos os dados/recibos da biblioteca são
removidos em cascata com o perfil. Recibos não possuem expiração nesta etapa.

Listas são privadas: sem publicação, colaboração, compartilhamento, likes ou feed.
O seletor de obras usa o catálogo carregado pelo app, sem busca remota adicional.
Testes HTTP/PostgreSQL cobrem migração dos favoritos, isolamento, CRUD, validação,
limites, concorrência, retry após exclusão e limpeza da conta; testes iOS cobrem
contrato HTTP e comportamento em falhas/reabertura, sem usar identidades reais.
