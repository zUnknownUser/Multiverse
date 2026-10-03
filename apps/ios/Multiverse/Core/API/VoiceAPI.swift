import Foundation

struct VoiceAvailability: Decodable, Sendable { let enabled: Bool; let maxParticipants: Int }
struct VoiceTicket: Decodable, Sendable { let id: String; let room: String; let serverURL: String; let token: String }
struct VoiceHeartbeat: Decodable, Sendable { let active: Bool }
struct VoiceDeparture: Decodable, Sendable { let left: Bool }
@MainActor protocol VoiceAPI: Sendable {
    func voiceAvailability() async throws -> VoiceAvailability
    func joinVoice(item: String, segment: Int, id: String) async throws -> VoiceTicket
    func renewVoice(_ id: String) async throws -> VoiceHeartbeat
    func leaveVoice(_ id: String) async throws -> VoiceDeparture
}
extension AccountAPIClient: VoiceAPI {
    func voiceAvailability() async throws -> VoiceAvailability { try await request("community/voice") }
    func joinVoice(item: String, segment: Int, id: String) async throws -> VoiceTicket {
        try await request("community/rooms/\(item)/voice/\(id)", method: "PUT", body: JSONSerialization.data(withJSONObject: ["segment": segment]))
    }
    func renewVoice(_ id: String) async throws -> VoiceHeartbeat { try await request("community/voice/\(id)/heartbeat", method: "PUT") }
    func leaveVoice(_ id: String) async throws -> VoiceDeparture { try await request("community/voice/\(id)", method: "DELETE") }
}
enum VoiceError: LocalizedError {
    case unavailable, full, blocked, ended, conflict, microphone
    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.text("A voz está indisponível agora. Tente novamente em instantes.")
        case .full: L10n.text("A sala de voz está cheia. Tente novamente quando alguém sair.")
        case .blocked: L10n.text("Não é possível entrar nesta conversa de voz devido a um bloqueio entre participantes.")
        case .ended: L10n.text("Você saiu da conversa de voz. Entre novamente para continuar.")
        case .conflict: L10n.text("Você já tem uma conexão de voz. Saia dela ou aguarde um minuto para tentar novamente.")
        case .microphone: L10n.text("Permita o acesso ao microfone nos Ajustes para falar. Você pode continuar ouvindo.")
        }
    }
}
