import Foundation
import LiveKit

struct VoiceParticipant: Identifiable, Equatable {
    let id: String; let name: String; let speaking: Bool; let muted: Bool; let local: Bool
}
@MainActor protocol VoiceConnection: AnyObject {
    var participants: [VoiceParticipant] { get }
    var connected: Bool { get }
    var reconnecting: Bool { get }
    var onChange: (() -> Void)? { get set }
    func connect(_ ticket: VoiceTicket) async throws
    func disconnect() async
    func microphone(enabled: Bool) async throws
}
@MainActor final class LiveVoiceConnection: NSObject, VoiceConnection, RoomDelegate {
    private var room: LiveKit.Room?
    var onChange: (() -> Void)?
    var connected: Bool { room?.connectionState == .connected }
    var reconnecting: Bool { room?.connectionState == .reconnecting }
    var participants: [VoiceParticipant] {
        guard let room, connected || reconnecting else { return [] }
        let local = room.localParticipant
        let everyone: [Participant] = [local] + room.remoteParticipants.values.sorted { ($0.identity?.stringValue ?? "") < ($1.identity?.stringValue ?? "") }
        return everyone.map { .init(id: $0.identity?.stringValue ?? "local", name: $0.name ?? L10n.text("Participante"), speaking: $0.isSpeaking, muted: !$0.isMicrophoneEnabled(), local: $0 === local) }
    }
    func connect(_ ticket: VoiceTicket) async throws {
        let next = LiveKit.Room(delegate: self)
        room = next
        // No tracks are captured or published on entry. Only the mic action publishes audio.
        try await next.connect(url: ticket.serverURL, token: ticket.token)
        onChange?()
    }
    func disconnect() async { let old = room; room = nil; await old?.disconnect(); onChange?() }
    func microphone(enabled: Bool) async throws {
        guard let room, connected else { throw VoiceError.ended }
        try await room.localParticipant.setMicrophone(enabled: enabled)
        onChange?()
    }
    private nonisolated func changed(_ room: LiveKit.Room) {
        Task { @MainActor [weak self] in
            guard let self, self.room === room else { return }; self.onChange?()
        }
    }
    nonisolated func room(_ room: LiveKit.Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) { changed(room) }
    nonisolated func room(_ room: LiveKit.Room, participantDidConnect participant: RemoteParticipant) { changed(room) }
    nonisolated func room(_ room: LiveKit.Room, participantDidDisconnect participant: RemoteParticipant) { changed(room) }
    nonisolated func room(_ room: LiveKit.Room, didUpdateSpeakingParticipants participants: [Participant]) { changed(room) }
    nonisolated func room(_ room: LiveKit.Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) { changed(room) }
}
