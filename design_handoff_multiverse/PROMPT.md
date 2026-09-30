# Prompt pro Claude Code

1. Crie um projeto novo no Xcode: **iOS App**, nome `Multiverse`, interface **SwiftUI**, iOS 17+.
2. Copie esta pasta `design_handoff_multiverse/` pra raiz do projeto.
3. Baixe a fonte Archivo no Google Fonts (`Archivo-VariableFont_wdth,wght.ttf`) e coloque em `design_handoff_multiverse/`.
4. Abra o terminal na pasta do projeto, rode `claude` e cole o texto abaixo:

---

```
Você vai construir o app iOS "Multiverse" em SwiftUI (iOS 17+), recriando com fidelidade total o protótipo em design_handoff_multiverse/.

Leia nesta ordem:
1. design_handoff_multiverse/README.md: especificação completa de todas as telas, textos, medidas, cores, interações e estado.
2. design_handoff_multiverse/reference/Multiverse v2.dc.html: protótipo em HTML. O <script> no fim do arquivo é a fonte da verdade da lógica; o template tem os estilos exatos (inline). Sempre que o README deixar alguma dúvida, confira aqui.
3. design_handoff_multiverse/swift/*.swift: base pronta (tokens, componentes, modelos, regras). Mova pro target do app e USE esses arquivos; não recrie tokens nem componentes que já existem.
4. design_handoff_multiverse/screenshots/*.png: capturas de cada tela; compare cada tela que você construir com a captura correspondente.
5. design_handoff_multiverse/data/sample-data.json: adicione ao bundle e carregue com SampleData.load().

Regras:
- Visual 100% igual ao protótipo: borda 2pt ink em tudo, sombras duras sem blur, retícula nas capas, fonte Archivo com os pesos e larguras do README, cores por universo. Não use estilos padrão do iOS (List, TabView visual, NavigationBar, Form); tudo é customizado.
- Todos os textos em português, exatamente como estão no README e no HTML.
- Estado global num AppStore @Observable injetado no ambiente, como descrito em "State Management".
- Tab bar customizada (Início, Busca, +, Avisos, Perfil) com NavigationStack por aba e botão "← VOLTAR" customizado.
- Registre a fonte em Info.plist (UIAppFonts) e confira se UIFont(name:) acha a Archivo; se não achar, ajuste o nome em Theme.swift.
- Onomatopeias (BurstOverlay) em todas as ações listadas no README, com haptic.
- Onboarding na primeira abertura, persistido com @AppStorage("mv-onboarded").

Ordem de trabalho:
1. Estrutura: AppStore, carregamento dos dados, reviews geradas, diário inicial, tab bar, navegação, toast, sheet de registro.
2. Home completa (Wrapped, universos, em alta, duelo, debate, feed, sugestões).
3. Obra (todas as seções, incluindo status de cânone, mapa de conexões e reviews) e Thread da review.
4. Universo (4 abas), Ordem, Lista.
5. Perfil (meu e de outros, afinidade, selos), Diário, Wrapped (com ImageRenderer + ShareLink), Busca, Avisos.
6. Onboarding e estados vazios e de carregamento.
7. Revise cada tela contra o HTML: medidas, textos, cores, animações.

Crie um arquivo por tela em Views/ e componentes extras em Components/. Compile ao fim de cada etapa e corrija os erros antes de seguir.
```
