import Foundation
import Testing
@testable import Multiverse

struct LogicTests {

    @Test func fmtAbbreviatesThousands() {
        #expect(Logic.fmt(312, locale: Locale(identifier: "pt-BR")) == "312")
        #expect(Logic.fmt(1240, locale: Locale(identifier: "pt-BR")) == "1,2 mil")
        #expect(Logic.fmt(999, locale: Locale(identifier: "pt-BR")) == "999")
        #expect(Logic.fmt(1000, locale: Locale(identifier: "pt-BR")) == "1 mil")
    }

    @Test func starsRendersHalfStar() {
        #expect(Logic.stars(4.5) == "★★★★½")
        #expect(Logic.stars(5) == "★★★★★")
        #expect(Logic.stars(0) == "")
    }

    @Test func seedIsDeterministic() {
        #expect(Logic.seed("w-wotlk") == Logic.seed("w-wotlk"))
        #expect(Logic.seed("w-wotlk") != Logic.seed("w-wc3"))
    }

    @Test func pollPercentsOnlyCountVoteAfterChoice() {
        let base = [10, 10]
        #expect(Logic.pollPercents(base: base, chosen: nil) == [50, 50])
        // Votar no índice 0 empurra o total pra 21, então 0 fica em 52% e 1 em 48%.
        let afterVote = Logic.pollPercents(base: base, chosen: 0)
        #expect(afterVote[0] > afterVote[1])
        #expect(afterVote[0] + afterVote[1] == 100 || afterVote[0] + afterVote[1] == 101)
    }

    @Test func starHintLabelsMatchRating() {
        #expect(Logic.starHint(5) == "★★★★★ · " + L10n.text("Obra-prima"))
        #expect(Logic.starHint(1) == "★ · " + L10n.text("Tempo perdido"))
    }

    @Test func verbMatchesItemType() {
        #expect(Logic.verb("Filme") == L10n.text("Assisti"))
        #expect(Logic.verb("HQ") == L10n.text("Li"))
        #expect(Logic.verb("Jogo") == L10n.text("Joguei"))
        #expect(Logic.verb("Personagem") == L10n.text("Avaliei"))
    }
}
