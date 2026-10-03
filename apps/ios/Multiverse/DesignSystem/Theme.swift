import SwiftUI
import UIKit

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    /// Cor que troca sozinha com o modo claro/escuro do sistema — a base do Modo Noir.
    /// `RootView` aplica `.preferredColorScheme` a partir de `AppStore.themePreference`,
    /// então "seguir o sistema" e o toggle manual nos Ajustes caem no mesmo mecanismo.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Design tokens (valores exatos do protótipo; Modo Noir em `2c-modo-noir.png`)

enum MV {
    enum C {
        static let ink   = Color(light: "#16130F", dark: "#F5F1E8")   // texto, bordas
        static let paper = Color(light: "#F5F1E8", dark: "#16130F")   // fundo das telas
        static let card  = Color(light: "#FFFDF8", dark: "#221E18")   // superfície de cards
        static let desk  = Color(light: "#E6E0D2", dark: "#2A251E")   // fundo de botão desabilitado
        static let muted = Color(light: "#6B655B", dark: "#A79E8F")   // texto secundário

        /// Sombras duras: pretas no claro, coloridas no Noir (ver `ComicCard`).
        static let shadow = Color(light: "#16130F", dark: "#2E5BE8")

        // Cores de universo são chapadas e não mudam de tema.
        static let marvel  = Color(hex: "#E4412F"), marvel2 = Color(hex: "#C9362A")
        static let dc      = Color(hex: "#2E5BE8"), dc2     = Color(hex: "#2349C4")
        // Amarelo editorial do app, independente dos universos.
        static let accent  = Color(hex: "#F4A814"), accent2 = Color(hex: "#D99210")

        static let divider = ink.opacity(0.15)
        /// Sempre escuro, nos dois temas — é o véu atrás de sheets/modais.
        static let scrim = Color.black.opacity(0.5)
    }

    enum R {
        static let xs: CGFloat = 3, sm: CGFloat = 4, poster: CGFloat = 6, md: CGFloat = 8
        static let lg: CGFloat = 10, xl: CGFloat = 12, xxl: CGFloat = 14, sheet: CGFloat = 20
    }

    static let stroke: CGFloat = 2
    static let pad: CGFloat = 16

    /// Sombras "duras" estilo gibi (offset x = y, sem blur)
    enum Shadow { static let s: CGFloat = 2, m: CGFloat = 3, l: CGFloat = 4 }
}

// MARK: - Tipografia
// Fonte: Archivo (Google Fonts, variável com eixos wght 400–900 e wdth 62–125).
// Registrada via Info.plist (UIAppFonts) a partir de Resources/Fonts.

enum MVFont {
    private static let wghtAxis: NSNumber = 0x77676874 // 'wght'
    private static let wdthAxis: NSNumber = 0x77647468 // 'wdth'

    /// Escala com o Texto Dinâmico do usuário (`UIFontMetrics`) — toda a tipografia do app
    /// passa por aqui, então isso sozinho cobre Acessibilidade → Texto Grande em todo lugar.
    static func archivo(_ size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100) -> Font {
        let base = UIFont(name: "Archivo", size: size)
            ?? UIFont(name: "Archivo-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .black)
        let key = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let desc = base.fontDescriptor.addingAttributes([key: [wghtAxis: weight, wdthAxis: width]])
        let fixed = UIFont(descriptor: desc, size: size)
        return Font(UIFontMetrics.default.scaledFont(for: fixed))
    }

    /// Títulos display: peso 900, largura expandida (125% por padrão)
    static func display(_ size: CGFloat, width: CGFloat = 125) -> Font { archivo(size, weight: 900, width: width) }
    /// Títulos de seção: 900, 115%, uppercase
    static func section(_ size: CGFloat = 20) -> Font { archivo(size, weight: 900, width: 115) }
    /// Labels / kickers: 800, uppercase, tracking ~0.1em
    static func label(_ size: CGFloat = 11) -> Font { archivo(size, weight: 800) }
    static func body(_ size: CGFloat = 13, weight: CGFloat = 500) -> Font { archivo(size, weight: weight) }
    static func bold(_ size: CGFloat = 13) -> Font { archivo(size, weight: 800) }
    static func black(_ size: CGFloat) -> Font { archivo(size, weight: 900) }
    /// Rótulo de placeholder de capa ("CAPA · HQ")
    static let mono = Font.system(size: 8, weight: .bold, design: .monospaced)
}

extension View {
    /// Kicker padrão: 10–11pt, 800, UPPERCASE, tracking 0.1–0.12em
    func kicker(_ size: CGFloat = 11) -> some View {
        self.font(MVFont.label(size)).textCase(.uppercase).tracking(size * 0.1)
    }
}
