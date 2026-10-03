import Foundation
import Testing
@testable import Multiverse

struct LayoutBehaviorTests {
    @Test(arguments: ["Lucas", "João", "Álvaro-José", "Alexandreeeeeeeeeeeeeeeeeeeeeeeeeeee", "   ", "李明", "🙂", "Anne Marie"])
    func usernameSuggestionsAlwaysFitTheServerRules(name: String) {
        var draft = NewAccountDraft(); draft.name = name
        #expect(draft.usernameSuggestions.count == 2)
        for suggestion in draft.usernameSuggestions {
            #expect(suggestion.range(of: "^[a-zA-Z0-9_.]{3,24}$", options: .regularExpression) != nil)
        }
    }
}
