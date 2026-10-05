import Foundation

struct AuthSession: Sendable, Equatable, Codable {
    let userID: String
    let email: String
    let handle: String
    var displayName: String? = nil
    var avatarColor: String? = nil
    var bio: String? = nil
    var needsProfile = false
    var onboarding: OnboardingState? = nil
    var avatarID: String? = nil
    var avatarPhotoID: String? = nil
}

enum AuthError: LocalizedError, Equatable {
    case invalidCredentials(attemptsRemaining: Int)
    case lockedOut(minutes: Int)
    case cancelled
    case unavailable
    case googleSignInFailed
    case networkUnavailable
    case recentLoginRequired
    case verificationCodeExpired, verificationUnavailable
    case invalidEmail, emailCredentialsInvalid, emailAlreadyRegistered, weakPassword
    case accountDisabled, tooManyRequests, emailProviderDisabled, invalidActionLink
    case emailNotVerified, profileIncomplete, sessionExpired, emailAuthenticationFailed
    case invalidCode
    case usernameTaken
    case apiNotConfigured, apiUnavailable, invalidProfile, onboardingConflict, suggestionsChanged, deletionPending
    case noPasswordForSocialAccount

    var errorDescription: String? {
        switch self {
        case .apiNotConfigured: return L10n.text("A conexão com o servidor ainda não foi configurada.")
        case .apiUnavailable: return L10n.text("Não foi possível acessar o servidor. Tente novamente.")
        case .invalidProfile: return L10n.text("Confira os dados do perfil e tente novamente.")
        case .onboardingConflict: return L10n.text("Seu progresso mudou em outro aparelho. Recarregue para continuar.")
        case .suggestionsChanged: return L10n.text("As sugestões de pessoas mudaram. Atualize e tente novamente.")
        case .deletionPending: return L10n.text("A exclusão da conta está em processamento. Tente novamente em instantes.")
        case .verificationCodeExpired: return L10n.text("Este código expirou. Solicite um novo código.")
        case .verificationUnavailable: return L10n.text("O envio de códigos está indisponível no momento. Tente novamente mais tarde.")
        case .invalidEmail: return L10n.text("Informe um e-mail válido.")
        case .emailCredentialsInvalid: return L10n.text("E-mail ou senha incorretos.")
        case .emailAlreadyRegistered: return L10n.text("Este e-mail já está cadastrado. Entre na sua conta ou recupere a senha.")
        case .weakPassword: return L10n.text("A senha não atende aos requisitos. Escolha uma senha mais forte.")
        case .accountDisabled: return L10n.text("Esta conta está desativada.")
        case .tooManyRequests: return L10n.text("Muitas tentativas. Aguarde um pouco antes de tentar novamente.")
        case .emailProviderDisabled: return L10n.text("O login por e-mail ainda não está habilitado. Tente novamente mais tarde.")
        case .invalidActionLink: return L10n.text("Este link é inválido, expirou ou já foi usado. Solicite um novo link.")
        case .emailNotVerified: return L10n.text("Confirme seu e-mail com o código de seis dígitos enviado.")
        case .profileIncomplete: return L10n.text("Complete seu nome para continuar.")
        case .sessionExpired: return L10n.text("Sua sessão expirou. Entre novamente.")
        case .emailAuthenticationFailed: return L10n.text("Não foi possível concluir. Tente novamente.")
        case .cancelled: return ""
        case .unavailable: return L10n.text("Esta opção estará disponível em breve. Por enquanto, continue com Google.")
        case .googleSignInFailed: return L10n.text("Não foi possível entrar com Google. Tente novamente.")
        case .networkUnavailable: return L10n.text("Confira sua conexão e tente novamente.")
        case .recentLoginRequired: return L10n.text("Para excluir sua conta, saia e entre novamente.")
        case .invalidCredentials(let n):
            return n > 0
                ? L10n.format("auth.remainingAttempts", n)
                : L10n.text("Senha incorreta.")
        case .lockedOut(let minutes):
            return L10n.format("auth.lockoutMinutes", minutes)
        case .invalidCode:
            return L10n.text("Código incorreto. Confira e tente de novo.")
        case .usernameTaken:
            return L10n.text("Esse usuário já existe.")
        case .noPasswordForSocialAccount:
            return L10n.text("Entrou com Apple ou Google? Você não tem senha no Multiverse. Volte e use o mesmo botão de antes.")
        }
    }
}

enum CommentPermission: String, CaseIterable, Sendable {
    case everyone = "Todos", following = "Quem sigo", nobody = "Ninguém"
}

struct AccountSettings: Sendable, Equatable, Codable {
    var publicDiary = true
    var whoCanComment: CommentPermission = .following
    var hideSpoilers = true
    var likesAndReplies = true
    var newDuelsAndDebates = false
}

extension CommentPermission: Codable {}

struct BlockedUser: Identifiable, Sendable, Codable {
    let id: String
    let handle: String
    let blockedOn: String
}

/// Rascunho preenchido ao longo do fluxo de criação de conta (telas 1–4).
struct NewAccountDraft: Equatable {
    var email = ""
    var password = ""
    var name = ""
    var username = ""
    var avatarColor = "#F4A814"
    var avatarID: String? = nil
    var bio = ""

    var usernameSuggestions: [String] {
        let first = name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? "lorista"
        let normalized = first.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let ascii = normalized.unicodeScalars.filter { (97...122).contains($0.value) || (48...57).contains($0.value) }
        let base = String(String.UnicodeScalarView(ascii)).prefix(17)
        let stem = base.isEmpty ? "lorista" : String(base)
        let seed = Logic.seed(stem)
        return ["\(stem).herois", "\(stem)\(100 + Int(seed % 900))"]
    }
}

/// Força de senha (barra de 4 segmentos + rótulo), usada na criação de conta e na troca de senha.
enum PasswordStrength: Int, CaseIterable {
    case fraca = 1, media, boa, excelente

    var label: String {
        switch self {
        case .fraca: return L10n.text("fraca")
        case .media: return L10n.text("média")
        case .boa: return L10n.text("boa")
        case .excelente: return L10n.text("excelente")
        }
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.contains(where: \.isUppercase) { score += 1 }
        if password.contains(where: { $0.isNumber || "!@#$%^&*()-_=+".contains($0) }) { score += 1 }
        if password.count >= 12 { score += 1 }
        return PasswordStrength(rawValue: max(1, score)) ?? .fraca
    }
}

/// Checklist de requisitos exibido abaixo do campo de senha.
struct PasswordRequirements: Equatable {
    let hasEightChars: Bool
    let hasUppercase: Bool
    let hasNumberOrSymbol: Bool

    init(_ password: String) {
        hasEightChars = password.count >= 8
        hasUppercase = password.contains(where: \.isUppercase)
        hasNumberOrSymbol = password.contains(where: { $0.isNumber || "!@#$%^&*()-_=+".contains($0) })
    }

    var allMet: Bool { hasEightChars && hasUppercase && hasNumberOrSymbol }
}
