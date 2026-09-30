# Fonte Archivo

A fonte variável Archivo está incluída no app e nos widgets. O arquivo original
`Archivo[wdth,wght].ttf` foi renomeado para `Archivo-VariableFont_wdth,wght.ttf`
para corresponder ao registro existente em `UIAppFonts`; o conteúdo não foi alterado.

Origem: [Google Fonts / Archivo](https://github.com/google/fonts/tree/95f4904fc8bcf26d3420fe315560c96417c6dec7/ofl/archivo).
A licença acompanha o arquivo em `Archivo-OFL.txt` e é copiada para os dois bundles.

`project.yml` inclui a fonte nos recursos dos targets. Após alterar os recursos,
execute `xcodegen generate`. `FontResourcesTests` verifica o empacotamento, o registro
via UIKit e os eixos de peso/largura usados por `MVFont`.
