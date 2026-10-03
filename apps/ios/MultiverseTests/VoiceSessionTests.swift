import Foundation
import Testing
@testable import Multiverse

@MainActor private final class VoiceAPIStub: VoiceAPI {
    var joining: CheckedContinuation<VoiceTicket, any Error>?
    var hold = false
    var departures: [String] = []
    var lastID = ""
    func voiceAvailability() async throws -> VoiceAvailability { .init(enabled: true, maxParticipants: 8) }
    func joinVoice(item: String, segment: Int, id: String) async throws -> VoiceTicket {
        lastID = id
        if hold { return try await withCheckedThrowingContinuation { joining = $0 } }
        return ticket(id)
    }
    func ticket(_ id: String) -> VoiceTicket { .init(id: id, room: "test", serverURL: "wss://test.livekit.cloud", token: "test") }
    func renewVoice(_ id: String) async throws -> VoiceHeartbeat { .init(active: true) }
    func leaveVoice(_ id: String) async throws -> VoiceDeparture { departures.append(id); return .init(left: true) }
}
@MainActor private final class VoiceConnectionStub: VoiceConnection {
    var participants: [VoiceParticipant] = []
    var connected = false
    var reconnecting = false
    var onChange: (() -> Void)?
    var microphoneChanges: [Bool] = []
    var connections = 0
    func connect(_ ticket: VoiceTicket) async throws { connections += 1; connected = true }
    func disconnect() async { connected = false }
    func microphone(enabled: Bool) async throws { microphoneChanges.append(enabled) }
}
@MainActor struct VoiceSessionTests {
    @Test func joinsMutedAndOnlyPublishesAfterExplicitMicrophoneAction() async {
        let api = VoiceAPIStub(), driver = VoiceConnectionStub()
        let voice = VoiceSession(factory: { driver }, permission: { true })
        #expect(driver.connections == 0)
        await voice.join(api: api, item: "work", segment: 0)
        #expect(voice.state == .connected)
        #expect(voice.muted)
        #expect(driver.microphoneChanges.isEmpty)
        await voice.toggleMicrophone()
        #expect(driver.microphoneChanges == [true])
        #expect(!voice.muted)
        await voice.toggleMicrophone()
        #expect(driver.microphoneChanges == [true, false])
        await voice.leave()
        #expect(voice.state == .idle)
        #expect(!driver.connected)
        #expect(api.departures == [api.lastID])
    }
    @Test func permissionDenialPreservesListeningWithoutPublishing() async {
        let api = VoiceAPIStub(), driver = VoiceConnectionStub()
        let voice = VoiceSession(factory: { driver }, permission: { false })
        await voice.join(api: api, item: "work", segment: 0)
        await voice.toggleMicrophone()
        #expect(voice.state == .connected)
        #expect(voice.muted)
        #expect(voice.error != nil)
        #expect(driver.microphoneChanges.isEmpty)
        await voice.leave()
    }
    @Test func cancellationBeforeTicketReturnsNeverConnectsAudio() async {
        let api = VoiceAPIStub(), driver = VoiceConnectionStub()
        api.hold = true
        let voice = VoiceSession(factory: { driver }, permission: { true })
        let work = Task { await voice.join(api: api, item: "work", segment: 0) }
        while api.joining == nil { await Task.yield() }
        await voice.leave()
        api.joining?.resume(returning: api.ticket(api.lastID))
        await work.value
        #expect(driver.connections == 0)
        #expect(voice.state == .idle)
        #expect(voice.muted)
    }
}
