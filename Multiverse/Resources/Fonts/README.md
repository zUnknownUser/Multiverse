# Fonte Archivo

Este projeto foi feito neste ambiente **sem acesso à internet**, então o arquivo de fonte
variável não pôde ser baixado. `Theme.swift` (`MVFont.archivo`) já cai pro system font em
peso `.black` se a Archivo não estiver registrada, então o app funciona sem este passo —
mas pra ficar pixel-perfeito, no Mac:

1. Baixe **Archivo** no Google Fonts: https://fonts.google.com/specimen/Archivo
2. Extraia `Archivo-VariableFont_wdth,wght.ttf` e coloque nesta pasta
   (`Multiverse/Resources/Fonts/`).
3. Rode `xcodegen generate` de novo — o arquivo é pego automaticamente porque
   `project.yml` inclui `Multiverse/Resources` inteiro como recurso do target.
4. Confirme que `Info.plist` já lista `Archivo-VariableFont_wdth,wght.ttf` em `UIAppFonts`
   (já está configurado).
5. No app, confira se `UIFont(name: "Archivo", size: 16)` resolve. Se o nome interno da
   fonte for diferente (ex.: `"Archivo-Variable"`), ajuste as strings de fallback em
   `MVFont.archivo(_:weight:width:)` em `DesignSystem/Theme.swift`.
