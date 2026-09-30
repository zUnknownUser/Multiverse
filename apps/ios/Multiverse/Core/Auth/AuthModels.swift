import Foundation

struct AuthSession: Sendable, Equatable, Codable {
    let userID: String
    let email: String
    let handle: String
    var displayName: String? = nil
    var avatarColor: String? = nil
    var bio: String? = nil
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
    case noPasswordForSocialAccount

    var errorDescription: String? {
        switch self {
        case .verificationCodeExpired: return "Este código expirou. Solicite um novo código."
        case .verificationUnavailable: return "O envio de códigos está indisponível no momento. Tente novamente mais tarde."
        case .invalidEmail: return "Informe um e-mail válido."
        case .emailCredentialsInvalid: return "E-mail ou senha incorretos."
        case .emailAlreadyRegistered: return "Este e-mail já está cadastrado. Entre na sua conta ou recupere a senha."
        case .weakPassword: return "A senha não atende aos requisitos. Escolha uma senha mais forte."
        case .accountDisabled: return "Esta conta está desativada."
        case .tooManyRequests: return "Muitas tentativas. Aguarde um pouco antes de tentar novamente."
        case .emailProviderDisabled: return "O login por e-mail ainda não está habilitado. Tente novamente mais tarde."
        case .invalidActionLink: return "Este link é inválido, expirou ou já foi usado. Solicite um novo link."
        case .emailNotVerified: return "Confirme seu e-mail com o código de seis dígitos enviado."
        case .profileIncomplete: return "Complete seu nome para continuar."
        case .sessionExpired: return "Sua sessão expirou. Entre novamente."
        case .emailAuthenticationFailed: return "Não foi possível concluir. Tente novamente."
        case .cancelled: return ""
        case .unavailable: return "Esta opção estará disponível em breve. Por enquanto, continue com Google."
        case .googleSignInFailed: return "Não foi possível entrar com Google. Tente novamente."
        case .networkUnavailable: return "Confira sua conexão e tente novamente."
        case .recentLoginRequired: return "Para excluir sua conta, saia e entre novamente."
        case .invalidCredentials(let n):
            return n > 0
                ? "Senha incorreta. Mais \(n) tentativa\(n > 1 ? "s" : "") antes de um bloqueio de 5 minutos."
                : "Senha incorreta."
        case .lockedOut(let minutes):
            return "Muitas tentativas. Tente de novo em \(minutes) minutos."
        case .invalidCode:
            return "Código incorreto. Confira e tente de novo."
        case .usernameTaken:
            return "Esse usuário já existe."
        case .noPasswordForSocialAccount:
            return "Entrou com Apple ou Google? Você não tem senha no Multiverse. Volte e use o mesmo botão de antes."
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
    var bio = ""
}

/// Força de senha (barra de 4 segmentos + rótulo), usada na criação de conta e na troca de senha.
enum PasswordStrength: Int, CaseIterable {
    case fraca = 1, media, boa, excelente

    var label: String {
        switch self {
        case .fraca: return "fraca"
        case .media: return "média"
        case .boa: return "boa"
        case .excelente: return "excelente"
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
