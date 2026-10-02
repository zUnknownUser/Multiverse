import Foundation
import Testing
@testable import Multiverse

struct LocalizationTests {
    @Test func socialPrivacyAndSafetyMessagesAreTranslated() {
        #expect(L10n.text("Diário privado: esta review fica só para você. Altere em Ajustes quando quiser.", preferredLanguages: ["en"]) == "Private diary: this review is just for you. You can change this in Settings.")
        #expect(L10n.text("Denúncia registrada. Esta review foi ocultada para você.", preferredLanguages: ["en-US"]) == "Report recorded. This review is now hidden from you.")
        #expect(L10n.text("Esta review não está mais disponível para você. Atualize o feed.", preferredLanguages: ["pt-BR"]) == "Esta review não está mais disponível para você. Atualize o feed.")
    }
    @Test func peopleStatesRespectThePreferredLanguage() {
        #expect(L10n.text("Agora você segue este lorista.", preferredLanguages: ["en-US"]) == "You’re now following this lorekeeper.")
        #expect(L10n.text("Não foi possível atualizar quem você segue. Tente novamente.", preferredLanguages: ["en"]) == "We couldn’t update who you follow. Please try again.")
        #expect(L10n.text("Nenhum lorista encontrado. Tente outro nome ou volte mais tarde.", preferredLanguages: ["en"]) == "No lorekeepers found. Try another name or come back later.")
        #expect(L10n.text("SALVANDO…", preferredLanguages: ["pt-BR"]) == "SALVANDO…")
    }
    @Test func launchAvailabilityMessagesRemainInformationalInBothLanguages() {
        #expect(L10n.text("Começar a explorar", preferredLanguages: ["en-US"]) == "Start exploring")
        #expect(L10n.text("Sem notas ainda", preferredLanguages: ["en"]) == "No ratings yet")
        #expect(L10n.format("Bem-vindo ao Multiverse · %1$@", arguments: ["1 of 2"], preferredLanguages: ["en"]) == "Welcome to Multiverse · 1 of 2")
        #expect(L10n.text("Faça o primeiro registro", preferredLanguages: ["pt-BR"]) == "Faça o primeiro registro")
        #expect(L10n.text("As sugestões mudaram. Confira os loristas disponíveis para continuar.", preferredLanguages: ["en"]) == "Suggestions have changed. Check the available lorekeepers to continue.")
    }
    @Test func activityStatesAndRecoveryAreAvailableInBothLanguages() {
        #expect(L10n.text("SUAS REVIEWS", preferredLanguages: ["en-US"]) == "YOUR REVIEWS")
        #expect(L10n.text("Avaliou esta obra.", preferredLanguages: ["en"]) == "Rated this work.")
        #expect(L10n.text("Ainda não há notas para esta obra.", preferredLanguages: ["en"]) == "There are no ratings for this work yet.")
        #expect(L10n.text("Não foi possível atualizar. Seus últimos dados continuam aqui.", preferredLanguages: ["en"]) == "Could not refresh. Your last loaded data is still here.")
        #expect(L10n.text("Ainda não há notas para esta obra.", preferredLanguages: ["pt-BR"]) == "Ainda não há notas para esta obra.")
    }
    @Test func catalogStatesAndCountsAreLocalizedWithoutPresentingEmptyContentAsAnError() {
        #expect(L10n.text("Catálogo em preparação", preferredLanguages: ["en-US"]) == "Catalog coming soon")
        #expect(L10n.text("Sem conexão", preferredLanguages: ["en-US"]) == "No connection")
        #expect(L10n.text("VERIFICAR NOVAMENTE", preferredLanguages: ["pt-BR"]) == "VERIFICAR NOVAMENTE")
        #expect(L10n.format("home.universesCount", arguments: [1], preferredLanguages: ["en"]) == "1 universe")
        #expect(L10n.format("home.universesCount", arguments: [3], preferredLanguages: ["pt-BR"]) == "3 universos")
        #expect(L10n.format("home.friendsCount", arguments: [1], preferredLanguages: ["pt-BR"]) == "1 amigo")
        #expect(L10n.format("home.friendsCount", arguments: [2], preferredLanguages: ["en"]) == "2 friends")
    }
    @Test func selectsFirstSupportedPreferredLanguage() {
        #expect(L10n.language(for: ["en-US", "pt-BR"]) == "en")
        #expect(L10n.language(for: ["en-GB"]) == "en")
        #expect(L10n.language(for: ["fr-FR", "en-AU", "pt-BR"]) == "en")
        #expect(L10n.language(for: ["pt-PT", "en-US"]) == "pt-BR")
        #expect(L10n.language(for: ["pt_BR"]) == "pt-BR")
        #expect(L10n.language(for: ["ja-JP"]) == "pt-BR")
        #expect(L10n.language(for: []) == "pt-BR")
        #expect(L10n.language() == L10n.language(for: Locale.preferredLanguages))
    }

    @Test func looksUpBothLanguagesAndFallsBackForUnknownText() {
        #expect(L10n.text("ENTRAR", preferredLanguages: ["en-US"]) == "SIGN IN")
        #expect(L10n.text("ENTRAR", preferredLanguages: ["pt-BR"]) == "ENTRAR")
        #expect(L10n.text("Senha", preferredLanguages: ["en-GB"]) == "Password")
        #expect(L10n.text("◆ ESCUDO", preferredLanguages: ["en"]) == "◆ SHIELD")
        #expect(L10n.text("unknown-key", preferredLanguages: ["en"]) == "unknown-key")
    }

    @Test func formatsArgumentsAndLiteralPercentWithoutChangingUserContent() {
        #expect(L10n.format("%1$@%% afinidade", arguments: ["82"], preferredLanguages: ["en"]) == "82% affinity")
        #expect(L10n.format("Seguindo %1$@. Seu feed ganhou reviews novas.", arguments: ["Ana 100% %@"], preferredLanguages: ["en"]) == "Following Ana 100% %@. Your feed has new reviews.")
        #expect(L10n.format("%1$@ de %2$@", arguments: ["2", "4"], preferredLanguages: ["en"]) == "2 of 4")
    }

    @Test func usesEnglishPluralRules() {
        #expect(L10n.format("comments.count", arguments: [0], preferredLanguages: ["en"]) == "0 comments")
        #expect(L10n.format("comments.count", arguments: [1], preferredLanguages: ["en"]) == "1 comment")
        #expect(L10n.format("comments.count", arguments: [2], preferredLanguages: ["en"]) == "2 comments")
        #expect(L10n.format("comments.count", arguments: [1], preferredLanguages: ["pt-BR"]) == "1 comentário")
        #expect(L10n.format("comments.count", arguments: [2], preferredLanguages: ["pt-BR"]) == "2 comentários")
        #expect(L10n.format("auth.lockoutMinutes", arguments: [1], preferredLanguages: ["en"]) == "Too many attempts. Try again in 1 minute.")
    }

    @Test func onboardingFollowMinimumUsesSingularAndPluralInBothLanguages() {
        #expect(L10n.format("onboarding.followMinimum", arguments: [1], preferredLanguages: ["en"]) == "FOLLOW AT LEAST\n1 LOREKEEPER.")
        #expect(L10n.format("onboarding.followMinimum", arguments: [2], preferredLanguages: ["en"]) == "FOLLOW AT LEAST\n2 LOREKEEPERS.")
        #expect(L10n.format("onboarding.followMinimum", arguments: [1], preferredLanguages: ["pt-BR"]) == "SIGA PELO MENOS\n1 LORISTA.")
        #expect(L10n.format("onboarding.followMinimum", arguments: [3], preferredLanguages: ["pt-BR"]) == "SIGA PELO MENOS\n3 LORISTAS.")
    }

    @Test func formatsCompactNumbersForTheSelectedLanguage() {
        #expect(Logic.fmt(1240, locale: Locale(identifier: "en-US")) == "1.2K")
        #expect(Logic.fmt(1000, locale: Locale(identifier: "en-GB")) == "1K")
        #expect(Logic.fmt(1240, locale: Locale(identifier: "pt-BR")) == "1,2 mil")
    }

    @Test func pluralMessagesKeepAdditionalArguments() {
        #expect(L10n.format("club.hiddenMessages", arguments: [1, "ch.", "8"], preferredLanguages: ["en"]) == "1 message about ch. beyond 8 is hidden until you get there.")
        #expect(L10n.format("club.hiddenMessages", arguments: [3, "ch.", "8"], preferredLanguages: ["en"]) == "3 messages about ch. beyond 8 are hidden until you get there.")
    }

    @Test func localizedFixturesPreserveDomainValuesAndRelationships() throws {
        func sample(_ language: String) throws -> SampleData {
            let url = try #require(L10n.resourceURL(named: "sample-data", extension: "json", preferredLanguages: [language]))
            return try JSONDecoder().decode(SampleData.self, from: Data(contentsOf: url))
        }
        func resources(_ language: String) throws -> RecursosData {
            let url = try #require(L10n.resourceURL(named: "recursos-data", extension: "json", preferredLanguages: [language]))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(RecursosData.self, from: Data(contentsOf: url))
        }
        let pt = try sample("pt-BR")
        let en = try sample("en-US")
        #expect(en.items.map(\.id) == pt.items.map(\.id))
        #expect(en.items.map(\.type) == pt.items.map(\.type))
        #expect(en.connections == pt.connections)
        #expect(en.readingOrders.map(\.steps) == pt.readingOrders.map(\.steps))
        #expect(en.canonStatus.mapValues(\.status) == pt.canonStatus.mapValues(\.status))
        #expect(en.items.first?.title == "Civil War")
        #expect(pt.items.first?.title == "Guerra Civil")
        let enResources = try resources("en")
        let ptResources = try resources("pt-BR")
        #expect(enResources.theories.map(\.status) == ptResources.theories.map(\.status))
        #expect(enResources.correctionSuggestions.map(\.changeType) == ptResources.correctionSuggestions.map(\.changeType))
        #expect(enResources.rooms.map(\.itemID) == ptResources.rooms.map(\.itemID))
        for message in enResources.clubMessages {
            let club = try #require(enResources.clubs.first { $0.id == message.clubID })
            let week = try #require(club.weeks.first { $0.week == message.week })
            #expect(week.segments.contains(message.segment))
        }
        #expect(ReportReason.spoiler.rawValue == "Spoiler sem aviso")
        #expect(CorrectionChangeType.canonStatus.rawValue == "Status de cânone")
        #expect(CommentPermission.following.rawValue == "Quem sigo")
    }

    @Test func appAndWidgetBundlesContainBothLocalizations() throws {
        for language in L10n.supportedLanguages {
            #expect(Bundle.main.localizations.contains(language))
        }
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugins.appendingPathComponent("MultiverseWidgets.appex")))
        for language in L10n.supportedLanguages {
            #expect(widget.localizations.contains(language))
            #expect(L10n.text("PRÓXIMO NA ORDEM", preferredLanguages: ["en"], bundle: widget) == "NEXT IN ORDER")
        }
    }
}
