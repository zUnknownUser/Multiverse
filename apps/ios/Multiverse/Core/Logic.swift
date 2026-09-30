import SwiftUI

/// Regras e números derivados — idênticos ao protótipo HTML, pra que os valores batam.
enum Logic {

    /// Hash determinístico usado pra gerar números "falsos mas estáveis". JS: [...s].reduce((a,c)=>(a*31+c)>>>0, 7)
    static func seed(_ s: String) -> UInt32 {
        var a: UInt32 = 7
        for u in s.utf16 { a = a &* 31 &+ UInt32(u) }
        return a
    }

    /// 1240 → "1,2 mil"; 312 → "312"
    static func fmt(_ n: Int, locale: Locale = L10n.locale) -> String {
        guard n >= 1000 else { return String(n) }
        let v = (Double(n) / 100).rounded() / 10
        let s = v.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
        return s + (locale.language.languageCode?.identifier == "en" ? "K" : " mil")
    }

    /// 4.5 → "★★★★½"
    static func stars(_ r: Double) -> String {
        guard r > 0 else { return "" }
        return String(repeating: "★", count: Int(r)) + (r.truncatingRemainder(dividingBy: 1) != 0 ? "½" : "")
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
    }

    /// Texto sobre cor: âmbar (Warcraft) usa ink; o resto usa branco-papel
    static func inkOn(hex: String) -> Color { hex.uppercased() == "#F4A814" ? MV.C.ink : MV.C.card }

    /// Capa: seed(id) % 3 → 0 = cor principal, 1 = preto com texto na cor, 2 = variante escura
    static func posterColors(item: Item, universe u: Universe) -> (bg: Color, fg: Color) {
        switch seed(item.id) % 3 {
        case 1: return (MV.C.ink, u.color)
        case 2: return (u.color2, u.inkColor)
        default: return (u.color, u.inkColor)
        }
    }

    /// Nº de registros de um item
    static func logCount(_ item: Item) -> Int { 800 + Int(seed(item.id) % 13000) }

    /// Nº de reviews de um item (≈ 1/4 dos registros)
    static func reviewCount(_ item: Item) -> Int { Int((Double(logCount(item)) / 4).rounded()) }

    /// Afinidade com o usuário logado (48–94%)
    static func compat(_ userId: String) -> Int { 48 + Int(seed(userId + "duda") % 47) }

    /// % do cânone visto = base do universo + nº de itens vistos daquele universo (máx 99)
    static func universePct(_ u: Universe, seenIds: Set<String>, items: [Item]) -> Int {
        min(99, u.base + items.filter { $0.uni == u.id && seenIds.contains($0.id) }.count)
    }

    /// Selo "Lorista de X" é conquistado com ≥ 50% do universo
    static func hasBadge(pct: Int) -> Bool { pct >= 50 }

    /// Nota que um amigo deu: review real se existir; senão, 1 em cada 3 amigos tem nota derivada da média
    static func friendRating(friend: String, item: Item, reviews: [Review]) -> Double? {
        if let r = reviews.first(where: { $0.user == friend && $0.item == item.id }) { return r.rating }
        let sd = seed(item.id + friend)
        guard sd % 3 == 0 else { return nil }
        let raw = item.avg + (Double(Int(sd % 5)) - 2) * 0.5
        return max(1, min(5, (raw * 2).rounded() / 2))
    }

    /// Resultado de votação: percentuais só aparecem DEPOIS do voto
    static func pollPercents(base: [Int], chosen: Int?) -> [Int] {
        let total = base.reduce(0, +) + (chosen == nil ? 0 : 1)
        return base.enumerated().map { i, v in Int((Double(v + (chosen == i ? 1 : 0)) / Double(total) * 100).rounded()) }
    }

    /// Verbo do log por tipo
    static func verb(_ type: String) -> String {
        ["Filme": L10n.text("Assisti"), "Série": L10n.text("Assisti"), "HQ": L10n.text("Li"), "Livro": L10n.text("Li"), "Jogo": L10n.text("Joguei")][type] ?? L10n.text("Avaliei")
    }
    static func verb3(_ type: String) -> String {
        ["Filme": L10n.text("assistiu"), "Série": L10n.text("assistiu"), "HQ": L10n.text("leu"), "Livro": L10n.text("leu"), "Jogo": L10n.text("jogou")][type] ?? L10n.text("avaliou")
    }

    /// Rótulo das estrelas no log
    static func starHint(_ r: Double) -> String {
        let labels = ["", L10n.text("Tempo perdido"), L10n.text("Fraco"), L10n.text("Ok"), L10n.text("Bom"), L10n.text("Ótimo"), L10n.text("Obra-prima")]
        let idx = Int(r.rounded(.up)) + (r == 5 ? 1 : 0)
        return "\(stars(r)) · \(labels[min(idx, 6)])"
    }

    /// Horas de lore por tipo de item (Wrapped)
    static func loreHours(_ type: String) -> Double {
        ["Jogo": 38, "Filme": 2.5, "Série": 5, "HQ": 3, "Livro": 9][type] ?? 1
    }

    /// Base de votos "Conta como cânone pra você?" (Sim / Não / Em parte)
    static func canonVoteBase(_ item: Item) -> [Int] {
        let sd = seed(item.id + "cn")
        return [50 + Int(sd % 40), 10 + Int((sd >> 3) % 30), 5 + Int((sd >> 6) % 20)].map { $0 * 17 }
    }

    /// Base de votos "Essencial pra entender {Universo}?" (Essencial / Opcional / Pode pular)
    static func essentialVoteBase(_ item: Item) -> [Int] {
        let sd = seed(item.id)
        return [40 + Int(sd % 40), 20 + Int((sd >> 3) % 30), 5 + Int((sd >> 5) % 20)].map { $0 * 23 }
    }

    /// Histograma de notas (10 barras, ½ … ★★★★★)
    static func ratingHistogram(_ item: Item) -> [Int] {
        let sd = seed(item.id)
        let bases = [1, 2, 3, 4, 6, 9, 12, 16, 13, 8]
        return bases.enumerated().map { i, b in
            max(1, b + Int(((item.avg - 4) * Double(i - 5)).rounded()) + Int((sd >> i) % 3))
        }
    }
}
