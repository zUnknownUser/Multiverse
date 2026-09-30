# Handoff: Multiverse — app iOS (SwiftUI)

## Overview
Multiverse é uma rede social pra fãs de universos fictícios (Marvel, DC, Warcraft no lançamento), no formato "diário + reviews + rede". O usuário registra e avalia **obras** (HQs, filmes, séries, jogos, livros), **personagens**, **eventos da lore** e **universos**. Ele segue outras pessoas, curte, comenta, vota em duelos e debates de cânone, segue ordens de leitura criadas pela comunidade e acompanha quanto de cada cânone já consumiu.

O motor do produto é o **efeito de rede**: tudo que um usuário faz vira conteúdo no feed de quem o segue.

## About the Design Files
Os arquivos em `reference/` são **referências de design feitas em HTML**. É um protótipo que mostra o visual e o comportamento pretendidos, **não código de produção**. A tarefa é **recriar esse design em SwiftUI nativo** (iOS 17+), seguindo os padrões do SwiftUI.

Para abrir a referência, sirva a pasta `reference/` com qualquer servidor local (ex.: `npx serve reference`) e abra `Multiverse v2.dc.html`. Toda a lógica e os dados estão no `<script>` no fim do arquivo. Esse script é a **fonte da verdade** pra qualquer dúvida de comportamento.

A pasta `swift/` já traz **código Swift inicial pronto**: tokens (`Theme.swift`), componentes base (`Components.swift`), modelos (`Models.swift`) e regras de negócio (`Logic.swift`). A pasta `data/sample-data.json` traz os dados de exemplo extraídos do protótipo. Use esses arquivos como base e construa as telas em cima deles.

## Fidelity
**High-fidelity.** Cores, tipografia, espaçamentos, bordas, sombras, textos e interações são finais. Recrie pixel a pixel. Medidas em pt equivalem aos px do protótipo (frame de 402×874, iPhone 16 Pro).

---

## Linguagem visual ("gibi/pop")
- **Fundo das telas:** `#F5F1E8` (papel). **Cards:** `#FFFDF8`. **Texto e bordas:** `#16130F` (ink).
- **Toda superfície tem borda de 2pt ink.** Cards importantes têm **sombra dura** (offset 3pt, ou 4pt nos heroes, sem blur, cor ink). Use `.comicCard()`.
- **Uma cor por universo, sempre chapada:**
  - Marvel `#E4412F` (escura `#C9362A`), texto `#FFFDF8`
  - DC `#2E5BE8` (escura `#2349C4`), texto `#FFFDF8`
  - Warcraft `#F4A814` (escura `#D99210`), texto `#16130F`
- **Retícula (halftone)** sobre toda capa, card de universo e hero colorido: pontos de raio 1pt a cada 6pt, ink a 20%. Use `Halftone()` num ZStack.
- **Tipografia única: Archivo** (variável; eixos wght 400–900 e wdth 62–125).
  - Display: 900, largura 125%, UPPERCASE, entrelinha ~0.85–0.9.
  - Títulos de seção: 900, largura 115%, 18–20pt, UPPERCASE.
  - Kickers: 10–11pt, 800, UPPERCASE, tracking 0.1–0.12em.
  - Corpo: 13–15pt, 500–600. Metadados: 11–12pt, 600–700.
- **Estrelas:** caractere ★/½ na cor do universo, com contorno ink de 0.5pt.
- **Capas são placeholders:** cor chapada + retícula + rótulo mono 8pt ("CAPA · HQ") + título em 900. A regra da cor está em `Logic.posterColors`. Deixe um ponto pra trocar por imagem real depois (`AsyncImage`).
- **Raios:** capas 6–8, botões 8–10, cards 12, heroes 14, bottom sheet 20, pílulas em cápsula.

## Navegação
- **Tab bar customizada** (não use a `TabView` padrão visualmente). Altura 88pt, fundo papel, borda superior de 2pt.
  - Itens: `Início`, `Busca`, **botão +** central, `Avisos`, `Perfil`.
  - Cada item é um botão de 70×40 com label 11pt/800 UPPERCASE. Ativo: fundo ink, texto papel. Inativo: transparente.
  - O **+** é um círculo de 54pt, `#E4412F`, com sombra dura de 3pt, elevado 18pt acima da barra, e abre o sheet de registro.
  - `Avisos` tem badge vermelho com o número de não lidos.
- Dentro de cada aba, use `NavigationStack` com **botão "← VOLTAR" customizado**: pílula `#FFFDF8`, borda de 2pt, sombra de 2pt, 12pt/800 UPPERCASE. Esconda a navigation bar nativa.
- Ao navegar, o scroll volta pro topo.

---

## Screens / Views
Os textos abaixo são exatos, em português.

### 0. Onboarding (primeira abertura; persistir `mv-onboarded` em `@AppStorage`)
Tela cheia, fundo papel, padding 62/16/34. No topo, 3 barras de progresso (altura 6, borda de 1.5; preenchida = ink).
1. **"Quais universos são seus?"** Kicker "Bem-vindo ao Multiverse · 1 de 3"; sub "Escolha onde você quer registrar, avaliar e discutir cânone."
   - Uma linha de 72pt por universo com nome (22pt, 900, largura 120%), "184 mil loristas · 1,2 mil itens" e um círculo ✓/+.
   - Selecionado: fundo na cor do universo, sombra de 4pt, deslocado (-2,-2), POW!. Não selecionado: fundo `#FFFDF8`.
   - Abaixo, 3 linhas tracejadas desabilitadas: "STAR WARS", "WARHAMMER 40K", "TOLKIEN", cada uma com "EM BREVE".
   - Botão "Continuar" só fica ativo com pelo menos 1 universo selecionado.
2. **"O que você já consumiu?"** Grade de 3 colunas com capas 2:3 dos universos escolhidos (sem personagens; até 15).
   - Tocar marca a capa: overlay ink 55% + ✓ num círculo de 36pt + escala 0.94.
   - O sub mostra a contagem ("N marcados. Sem nota por enquanto, dá pra avaliar depois.").
   - O botão diz "Pular" se nada estiver marcado.
3. **"Siga pelo menos 3 loristas"** Lista de usuários (avatar de 38pt, nome + selo, "{afinidade}% afinidade · {bio}", botão Seguir/Seguindo) e o link "Seguir todos".
   - Os primeiros da lista são os que têm selo nos universos escolhidos, depois ordenados por afinidade.
   - O botão diz "Siga mais N" (desabilitado: fundo `#E6E0D2`, texto `#6B655B`) até chegar a 3; depois vira "Montar meu feed".
4. **Carregando:** "MONTANDO SEU MULTIVERSO" (40pt) e "Puxando reviews, votos e listas de N loristas em N universos…".
   - Grade de 6 capas-esqueleto nas cores dos universos, com opacidade pulsando entre 0.35 e 1 (1.1s, defasagem de 0.12s entre elas).
   - Após 1.7s, vai pra Home e mostra o toast "Feed pronto. Bem-vindo ao Multiverse."
- Botão principal: 54pt, `#E4412F`, sombra de 3pt. Botão voltar: quadrado de 54pt.

### 1. Home
De cima pra baixo (padding horizontal de 16):
- **Header:**
  - "MULTIVERSE" (30pt, 900, largura 125%, tracking -0.02em).
  - Abaixo, "6 amigos · 3 universos" (kicker).
  - À direita, avatar de 40pt com as iniciais do usuário, que abre o Perfil.
- **Faixa Wrapped:**
  - Faixa ink com retícula clara e raio 10.
  - Dentro, um selo "NOVO" vermelho girado -4°, o texto "Seu setembro no Multiverse está pronto" e uma seta →.
  - Tocar abre o Wrapped.
- **Grade de 3 universos:**
  - Cards de 104pt de altura, cada um na cor do seu universo, com retícula.
  - Conteúdo de cada card: nome (14pt, 900), "1,2 mil ativos agora", % visto (22pt, 900) e uma barra de 6pt.
  - Tocar abre a página do universo.
- **"Em alta no seu círculo"** (+ link "VER TUDO", que vai pra Busca):
  - Carrossel horizontal de capas 96×144.
  - Abaixo de cada capa: "★ 4,7" e "3 amigos registrou" (ou "12 mil esta semana").
- **Duelo do dia:**
  - Cabeçalho ink: "DUELO DO DIA · 1/4" e o total de votos.
  - A pergunta em 19pt/900.
  - Duas capas de 170pt lado a lado, com um círculo "VS" de 44pt no centro.
  - Tocar num lado vota nele: KRAK!, a porcentagem (34pt) aparece em cada lado, o escolhido gira -1.5° com escala 1.02 e o outro fica com opacidade 0.55.
  - Depois do voto aparece "Você está com a maioria/minoria…" e o botão "PRÓXIMO DUELO →". Antes do voto: "Toque num lado pra votar".
- **Debate da semana:**
  - Cabeçalho âmbar: "DEBATE DA SEMANA · WARCRAFT", "O CATACLISMO" (28pt) e o texto.
  - 3 opções: "Melhor momento da lore", "Pior retcon de todos" e "Os dois ao mesmo tempo".
  - Barras só aparecem depois do voto, animadas em 0.5s (curva .2,.8,.2,1); a opção escolhida fica âmbar. BAM! no voto.
  - Rodapé: "4,8 mil votos · vote pra ver o resultado" e "612 comentários".
- **"Do seu pessoal"** (à direita, "seguindo N"): card de review do feed (ver Componentes). Mostra até 8, as mais recentes primeiro, só de quem você segue e as suas.
  - Estado vazio: card tracejado com "SILÊNCIO NO MULTIVERSE" e "Seu feed ganha vida quando você segue gente. Comece pelos loristas abaixo."
- **"Loristas pra seguir"** ("Quanto mais gente você segue, melhor fica o seu feed."):
  - Carrossel de cards de 138pt.
  - Cada card: avatar de 52pt, nome, bio, pílula "{N}% afinidade" na cor do selo e botão Seguir (ink) / Seguindo (claro). ZAP! + toast ao seguir.

### 2. Busca
- Título "BUSCA".
- Campo de busca: 48pt, raio 12, sombra de 3pt, com "⌕" e o placeholder "Obra, personagem, evento, pessoa…".
- Filtros em pílula: Tudo, Obras, Personagens, Eventos, Pessoas. Ativo = ink.
- Linhas de resultado:
  - Miniatura 44×64 (circular 44×44 pra personagens e pessoas).
  - Título 14/800 e "Universo · ano · ★ 4,3 · 12 mil registros".
  - À direita, pílula com o tipo na cor do universo.
- Sem busca, mostra "Mais registrados esta semana". Sem resultados: "Nada nesse canto do multiverso."

### 3. Avisos (atividade)
- "ATIVIDADE" e "O que o pessoal fez com o que você postou."
- Lista de notificações: avatar de 34, "**Nome** texto **Obra**", citação opcional (borda esquerda de 3pt) e horário.
  - À direita: botão "Seguir" (em notificações de novo seguidor) ou miniatura da capa.
  - Tocar abre a review ou o perfil.
- "Top loristas da semana": ranking de 1 a 4 com "48 reviews · 9,1 mil curtidas" e um botão Seguir pequeno.
- Abrir a aba zera o badge.

### 4. Perfil (o seu e o de outros)
- **Hero ink:**
  - Avatar de 64 com borda papel de 3pt, nome (22pt, 900, UPPERCASE) e "@handle · bio".
  - 3 caixas de estatística com borda papel: Registros, Seguidores e Seguindo.
  - No seu perfil: botões "DIÁRIO" e "+ REGISTRAR". No perfil de outros: botão "SEGUIR" (claro) / "SEGUINDO" (contorno).
- **Seu perfil:** card Wrapped vermelho com retícula, "MULTIVERSE WRAPPED", "SEU SETEMBRO" e →.
- **Perfil de outros, card de afinidade:**
  - Cabeçalho âmbar com retícula: "73%" em 44pt/900, "AFINIDADE COM VOCÊ" e uma frase:
    - acima de 78%: "Almas gêmeas de cânone."
    - acima de 62%: "Gostos parecidos, brigas saudáveis."
    - senão: "Discordam bastante. Rende bons debates."
  - Barras por universo, "Concordam em: …" e "Brigam por: …".
- **Cânone consumido:** barras de 16pt por universo, na cor do universo.
- **Selos:** grade de 3 com losango de 38pt girado 45°. Conquistado = cor do universo + ★ + "Conquistado". Bloqueado = borda tracejada, "?", "faltam N%" e opacidade 0.75.
- **Favoritos:** 4 capas.
- **Reviews recentes:** linha com capa 40×60, estrelas, texto em 2 linhas e "♥ N · N comentários".
- **Listas** (só no seu perfil): 4 capas empilhadas (sobreposição de -14) e "N itens · ♥ N · N comentários".

### 5. Universo
- **Hero:**
  - Card na cor do universo com sombra de 4pt.
  - Kicker "UNIVERSO · {canon}", nome (40pt, 900, largura 125%) e tagline.
  - Barra de progresso de 10pt com "58% visto".
- **Abas em pílula quadrada:** Geral, Linha do tempo, Ordens e Personagens.
- **Geral:**
  - 3 estatísticas: Itens no cânone, Membros e Ativos agora.
  - "Mais bem avaliados": carrossel.
  - "Reviews populares": 3 cards de review ordenados por curtidas, cada um com "Nome sobre Obra".
- **Linha do tempo:**
  - "Onde seu pessoal está": chips com avatar e "Nina · Ano 27".
  - Lista vertical com trilho de 2pt e ponto de 20pt, preenchido e com ✓ se já foi visto.
  - Cada item mostra a era (kicker), o título (17pt/900) e "[Tipo] nota · ★ 4,7".
  - Abaixo do item, avatares sobrepostos dos amigos que já passaram por ele e "Nina já passou por aqui" / "3 amigos já passaram por aqui".
- **Ordens:**
  - Texto: "Ordens montadas e votadas pela comunidade. A mais votada sobe pro topo."
  - Cada card tem um botão de voto ▲ de 52pt de largura (ativo = cor do universo, BOOM!), título, "por @x · N itens · N seguem" e barra de progresso "2/6".
  - Ordenado por votos.
- **Personagens:** grade de 3 com retratos circulares de 92pt, "★ 4,6 · 12 mil registros".

### 6. Obra / Personagem / Evento
- **Topo:**
  - Capa 118×177 com sombra de 4pt.
  - Ao lado: pílula do universo, que leva ao universo; título (22pt, 900, largura 105%); "Tipo · ano · canon"; média (30pt/900) e "12 mil registros · 3 mil reviews".
- **Ações:** grade 2fr/1fr/1fr com altura de 46.
  - "REGISTRAR" / "REGISTRAR DE NOVO" / "AVALIAR" (este pra personagem e evento), na cor do universo.
  - "+ QUERO" ↔ "✓ NA LISTA".
  - "♥ CURTIR", vermelho quando ativo.
  - Se o usuário já registrou, aparece "Sua nota: ★★★★".
- **Amigos que registraram:** kicker com "média deles ★ 4,2" e carrossel de avatares de 40 com as estrelas embaixo.
- **Descrição** (14pt/500).
- **Status de cânone:**
  - Selo girado -2° com o status: Cânone (ink), Variante (`#2E5BE8`), Retconado (`#E4412F`) ou Contestado (`#F4A814`, texto ink). Ao lado, a nota explicativa.
  - Pergunta "Conta como cânone pra você?" com 3 botões: Sim, Não e Em parte. O % aparece depois do voto, e o escolhido fica na cor do universo. ZAP!
- **Voto da comunidade:**
  - Cabeçalho na cor do universo: "Essencial pra entender {Universo}?"
  - Barras: Essencial, Opcional e Pode pular, reveladas depois do voto.
- **Notas da comunidade:** histograma de 10 barras (60pt). As 2 últimas ficam na cor do universo e o resto em `#FFFDF8`. Legenda "½ … ★★★★★".
- **Na linha do tempo:** 3 colunas (Antes / "Aqui · {era}" na cor do universo / Depois), clicáveis, e o link "Ver tudo", que abre o universo na aba Linha do tempo.
- **Mapa de conexões:**
  - Caixa de 270pt com pontilhado de 10pt.
  - Nó central de 62pt com o texto "AQUI". Até 6 nós em elipse (raio 118×84) de 46pt, circulares pra personagens, raio 4 pra eventos e raio 8 pra obras.
  - Linhas de 2pt ink do centro até cada nó. Label abaixo com fundo branco. Tocar navega.
- **Reviews:**
  - Segmentado "Populares / Amigos".
  - Até 5 cards de review com selo e a tag "SEGUINDO".
  - Vazio: "Nenhum amigo escreveu sobre isso ainda. Seja o primeiro."

### 7. Thread da review
- Mini-cabeçalho com a capa 44×66, "Universo · Tipo" e o título; tocar abre a obra.
- **Card da review** (sombra de 4pt):
  - Avatar de 36, nome + selo, horário e estrelas de 17pt.
  - Texto de 15pt, borrado se tiver spoiler até ser tocado.
  - Pílula "♥ 214 curtidas".
- **Comentários:**
  - Título "N comentários".
  - Cada comentário: avatar de 30, balão com raio 4/12/12/12 (nome, horário, texto) e ♥ + contagem à direita (vermelho quando curtido).
- **Campo de resposta:**
  - Avatar do usuário, campo em cápsula de 42pt ("Responder… (teorias bem-vindas)") e botão "ENVIAR" ink. Enter também envia.
  - Toast: "{Nome} vai ser notificado" (ou "Resposta publicada" se a review for sua).

### 8. Ordem de leitura/assistir
- **Hero na cor do universo:**
  - Kicker "ORDEM DA COMUNIDADE · {Universo}", título (28pt) e "por @x · N itens · N seguem".
  - Barra de progresso "2 de 6".
  - Botões "▲ 3,2 mil" (votar) e "SEGUIR ORDEM" / "✓ SEGUINDO".
- **Passos:** número (18pt/900), capa 32×48, título (riscado se já visto), "Tipo · ano · ★" e checkbox de 34 (✓ na cor do universo) que marca como visto.

### 9. Lista
- Kicker "LISTA DE @duda.lore", título (30pt), descrição, "♥ N" (curtível) e "N comentários".
- Grade de 3 capas 2:3, com o número da posição num círculo ink de 24 no canto superior esquerdo.

### 10. Diário
- "DIÁRIO" e "N registros em 2026 · visível pros seus seguidores".
- Agrupado por mês: etiqueta ink "SETEMBRO" + linha de 2pt.
- Cada linha: dia (24pt/900), capa 34×51, título/meta, estrelas e ♥/↻.

### 11. Wrapped (mensal)
Pilha de cards (gap de 12):
1. Hero vermelho com retícula de 7pt: "MULTIVERSE WRAPPED · SET 2026", "SEU MÊS NO CÂNONE" (44pt) e "@duda.lore".
2. Grade 1.2fr/1fr:
   - Registros: o número em 72pt/900 e "+N que agosto".
   - Horas de lore, em card ink: o número em 44pt e "≈ N dias em outras realidades". As horas vêm do tipo de cada registro: Jogo 38, Filme 2.5, Série 5, HQ 3, Livro 9, outros 1.
3. Universo do mês, na cor dele e com retícula: nome em 38pt e "N registros · N% do cânone visto".
4. Nota mais alta: capa, título e estrelas; tocar abre a obra.
5. Arquétipo, em card azul `#2E5BE8`: "O ARQUIVISTA" e o texto.
6. Review mais curtida: a citação, "♥ N" e a obra.
7. Botão "COMPARTILHAR NOS STORIES": ink, 54pt, sombra dura vermelha. Gere a imagem com `ImageRenderer` + `ShareLink`.

### 12. Sheet de registro (botão + ou "Registrar")
- Bottom sheet customizado: raio 20 no topo, borda de 2, alça de 44×5, scrim ink 50%, entrada deslizando de baixo (0.28s, curva .2,.8,.2,1).
- **Sem item escolhido:** "O QUE VOCÊ VIU, LEU OU JOGOU?" + grade de 3 capas.
- **Com item:**
  - Capa 52×78, "{Assisti/Li/Joguei} · Hoje, 29 set", título e "Universo · Tipo".
  - **Nota:** 5 botões de 50pt. Tocar no mesmo botão de novo marca meia estrela (½). Preenchido = cor do universo.
  - O hint mostra o rótulo da nota ("★★★★ · Ótimo"; veja `Logic.starHint`) ou, sem nota, "Toque de novo pra meia estrela".
  - Pílulas: "♥ Curti", "↻ Revisitei" e "⚠ Contém spoiler".
  - Campo de texto de 92pt: "Escreva sua review… teorias de cânone são bem-vindas."
  - "Vai aparecer no feed dos seus 312 seguidores e na página de {obra}."
  - Botão "PUBLICAR" na cor do universo.
- **Ao publicar:** cria a entrada no diário (dia 29, Setembro), marca como visto, cria a review no topo do feed e mostra o toast "Publicado no feed do seu pessoal".

---

## Componentes reutilizáveis
- **Card de review do feed:**
  - Linha 1: avatar de 28, "**Nome** [SELO] {leu/assistiu/jogou/avaliou} <u>Obra</u>".
  - Estrelas de 15pt.
  - Texto de 13pt/1.4. Com spoiler: borrado (raio 6) com a pílula "SPOILER · TOQUE PARA VER" por cima; tocar revela.
  - À direita, capa 58×87.
  - Rodapé separado por linha de 1.5pt (ink 15%): pílula "♥ N" (vermelha `#E4412F` quando curtida, POW!), pílula "N comentários" / "Comentar" (abre a thread) e o horário à direita.
- **Selo (BadgeChip):** 8pt/900 na cor do universo do selo do usuário ("AZEROTH", "TERRA-616", "MULTI-DC").
- **Toast:** cápsula ink, texto papel 13/800, 104pt acima da base. Aparece e some em 2.4s, subindo 10pt ao entrar.
- **Onomatopeia (BurstOverlay):** POW! (curtir), BAM! (votar em debate), ZAP! (seguir, cânone), KRAK! (duelo), BOOM! (votar em ordem), SHARE! (Wrapped).
  - Aparece no ponto do toque: escala 0.3 → 1.2 → 1, rotação -14° → -4°, sobe 30pt e some em 0.75s.
  - Fundo na cor da ação, borda de 2, sombra de 3. Acompanha um haptic `.medium`.

## Interações e comportamento
- **Votações** (debate, duelo, cânone, essencial): os percentuais **só aparecem depois do voto**. O voto soma +1 ao total. Veja `Logic.pollPercents`.
- **Spoilers:** borrados até serem tocados. Tocar num texto borrado não abre a thread; o primeiro toque só revela.
- **Seguir:** muda o feed na hora, atualiza o contador de seguidores do outro perfil e mostra o toast "Seguindo {Nome}. Seu feed ganhou reviews novas." (exceto no onboarding).
- **Visto:** um item conta como visto se estiver no diário ou marcado numa ordem ou no onboarding. Desmarcar numa ordem deixa de contar. Isso afeta o % do universo, a linha do tempo, as ordens e os selos (≥ 50%).
- **Amigos que registraram:** `Logic.friendRating`.

## State Management
Use um `@Observable` `AppStore` injetado no ambiente. Ele guarda:
- **Navegação:** `tab`, `path` por aba e `unreadCount` (4 no início).
- **Rede:** `follows: Set<String>` (padrão: nina, caio, leo, bia, rafa, tati; vazio se o onboarding estiver ativo).
- **Conteúdo:** `reviews: [Review]` (das amostras + 2 geradas por item, ver abaixo) e `diary: [DiaryEntry]`.
- **Toggles:** `likedReviews`, `likedComments`, `likedItems`, `wantList`, `revealedSpoilers`, `checks: [String: Bool]`, `orderVotes`, `orderFollows`, `likedLists`.
- **Votos:** `pollVote: Int?`, `duelIndex`, `duelVotes: [Int: Int]`, `canonVotes: [String: Int]`, `essentialVotes: [String: Int]`.
- **Registro:** `logDraft` (itemId, rating, liked, rewatch, spoiler, text).
- **Onboarding:** `onboardingStep` e `onboardingUniverses`.

**Reviews geradas:** pra cada item `i`, gere 2 reviews (`j` = 0 e 1):
- **Autor:** `["gui","mari","joao","lu"][(i+j)%4]`.
- **Texto:** `genericReviewTexts[seed(id+j)%5]`.
- **Nota:** média ±0.5, arredondada pra .5 e limitada entre 1 e 5.
- **Curtidas:** `20 + seed%400`.
- **Horário:** "{2+seed%20} dias".
- **Comentário:** 1 comentário "Concordo demais." quando `seed` for ímpar.

**Diário inicial:**
- w-crimes 27/Set ★4.5 ♥
- w-wotlk 24/Set ★5 ↻
- d-crise 19/Set ★4
- m-loki 12/Set ★3.5
- w-wc3 3/Set ★5 ♥
- d-watchmen 28/Ago ★5 ♥
- m-civil 20/Ago ★3
- e-cataclismo 14/Ago ★3.5
- d-flash 9/Ago ★4

Para o backend (fase 2): Supabase ou Firebase, com tabelas equivalentes aos modelos em `Models.swift`, mais `follows`, `votes` (alvo polimórfico) e `likes`.

## Design Tokens
Todos estão em `swift/Theme.swift`:
- **Cores:** ink `#16130F`, paper `#F5F1E8`, card `#FFFDF8`, desk `#E6E0D2`, muted `#6B655B`, Marvel `#E4412F`/`#C9362A`, DC `#2E5BE8`/`#2349C4`, Warcraft `#F4A814`/`#D99210`.
- **Espaçamento:** padding de tela 16. Seções separadas por 18–26 no topo. Gaps de 6, 8, 10, 12 e 14.
- **Raios:** 3, 4, 6, 8, 10, 12, 14, 20 e cápsula.
- **Bordas:** 2pt (1.5 em chips pequenos, 3 no avatar do perfil).
- **Sombras duras:** 2, 3 e 4pt de offset, sem blur.
- **Retícula:** 6pt de espaçamento, 1.1pt de raio, ink a 20%.

## Assets
- Fonte **Archivo**, do Google Fonts (OFL): baixe `Archivo-VariableFont_wdth,wght.ttf`.
- Ícones: nenhum, só caracteres (★ ½ ♥ ↻ ⚠ ▲ ✓ → ← ⌕ +).
- Capas e retratos são placeholders; troque por imagens licenciadas depois.

## Screenshots
A pasta `screenshots/` tem 28 capturas (402×874) das telas e estados principais, numeradas na ordem do fluxo: onboarding (01–04), home (05–07), obra (08–11), thread (12), universo (13–16), ordem (17), perfis (18–20), Wrapped (21–22), busca (23), avisos (24), diário (25), lista (26) e sheet de registro (27–28). Use as capturas pra comparar visualmente; para medidas exatas, confira o HTML.

## Files
- `screenshots/*.png`: capturas de referência de cada tela.
- `reference/Multiverse v2.dc.html`: protótipo completo (template + lógica + dados).
- `reference/ios-frame.jsx`, `reference/support.js`: necessários pra abrir o HTML.
- `data/sample-data.json`: dados de exemplo (31 itens, 11 usuários, 11 reviews, ordens, listas, duelos, status de cânone).
- `swift/Theme.swift`, `swift/Components.swift`, `swift/Models.swift`, `swift/Logic.swift`: base Swift pronta.
- `PROMPT.md`: o prompt pra colar no Claude Code.
