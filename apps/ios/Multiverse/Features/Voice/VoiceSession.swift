import Foundation
import Observation
import AVFAudio

@MainActor @Observable final class VoiceSession {
    enum State { case idle, connecting, connected, reconnecting, leaving }
    private(set) var state: State = .idle
    private(set) var participants: [VoiceParticipant] = []
    private(set) var muted = true
    private(set) var changingMic = false
    var error: String?
    private var generation = 0
    private var id: String?
    private var api: (any VoiceAPI)?
    @ObservationIgnored private var connection: (any VoiceConnection)?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private let factory: () -> any VoiceConnection
    @ObservationIgnored private let permission: () async -> Bool
    var active: Bool { state != .idle }
    init(factory: @escaping () -> any VoiceConnection = { LiveVoiceConnection() }, permission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() }) {
        self.factory = factory; self.permission = permission
    }
    func join(api: any VoiceAPI, item: String, segment: Int) async {
        guard state == .idle else { return }
        generation += 1; let attempt = generation
        let sessionID = UUID().uuidString.lowercased()
        self.api = api; id = sessionID; error = nil; muted = true; state = .connecting
        let driver = factory(); connection = driver
        driver.onChange = { [weak self] in self?.update(attempt: attempt) }
        do {
            let ticket = try await api.joinVoice(item: item, segment: segment, id: sessionID)
            guard generation == attempt else { _ = try? await api.leaveVoice(sessionID); return }
            guard ticket.id == sessionID, let url = URL(string: ticket.serverURL), url.scheme == "wss", url.host?.hasSuffix(".livekit.cloud") == true, !ticket.token.isEmpty else { throw VoiceError.unavailable }
            try await driver.connect(ticket)
            guard generation == attempt else { await driver.disconnect(); _ = try? await api.leaveVoice(sessionID); return }
            state = .connected; participants = driver.participants
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    guard let self, self.generation == attempt else { return }
                    do {
                        let result = try await api.renewVoice(sessionID)
                        guard result.active else { throw VoiceError.ended }
                    } catch {
                        guard self.generation == attempt else { return }
                        self.error = error.localizedDescription; await self.leave(); return
                    }
                }
            }
        } catch {
            guard generation == attempt else { return }
            self.error = error is VoiceError || error is AuthError || error is CommunityError ? error.localizedDescription : VoiceError.unavailable.localizedDescription
            await leave()
        }
    }
    func toggleMicrophone() async {
        guard state == .connected, !changingMic, let connection else { return }
        changingMic = true; let attempt = generation
        defer { if generation == attempt { changingMic = false } }
        let enabling = muted
        if enabling {
            let allowed = await permission()
            guard generation == attempt else { return }
            if !allowed { error = VoiceError.microphone.localizedDescription; return }
        }
        guard generation == attempt, state == .connected else { return }
        do {
            try await connection.microphone(enabled: enabling)
            guard generation == attempt else { return }
            muted = !enabling; error = nil; participants = connection.participants
        } catch { if generation == attempt { self.error = VoiceError.unavailable.localizedDescription } }
    }
    func leave() async {
        guard state != .idle && state != .leaving else { return }
        generation += 1; heartbeat?.cancel(); heartbeat = nil
        let old = connection, oldID = id, oldAPI = api
        connection = nil; id = nil; api = nil; muted = true; changingMic = false; participants = []; state = .leaving
        await old?.disconnect()
        state = .idle
        if let oldID, let oldAPI { _ = try? await oldAPI.leaveVoice(oldID) }
    }
    private func update(attempt: Int) {
        guard generation == attempt, let connection else { return }
        participants = connection.participants
        if connection.connected { state = .connected }
        else if connection.reconnecting { state = .reconnecting }
        else if state == .connected || state == .reconnecting {
            Task {
                guard generation == attempt else { return }
                error = VoiceError.ended.localizedDescription; await leave()
            }
        }
    }
}
