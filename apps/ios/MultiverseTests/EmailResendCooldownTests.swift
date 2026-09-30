import Foundation
import Testing
@testable import Multiverse

@MainActor
struct EmailResendCooldownTests {
    @Test func deadlineExpiresWithoutAnyTimerTicksAndRoundsUpPartialSeconds() {
        var date = Date(timeIntervalSince1970: 1_000)
        let cooldown = EmailResendCooldown(now: { date })
        cooldown.recordSend(for: .passwordReset, email: "test@example.com")
        #expect(cooldown.remaining(for: .passwordReset, email: "test@example.com") == 60)
        date += 59.5
        #expect(cooldown.remaining(for: .passwordReset, email: "test@example.com") == 1)
        date += 0.5
        #expect(cooldown.remaining(for: .passwordReset, email: "test@example.com") == 0)
    }

    @Test func recipientsAndPurposesHaveIndependentDeadlines() {
        let cooldown = EmailResendCooldown()
        cooldown.recordSend(for: .passwordReset, email: " Test@Example.com \n")
        #expect(cooldown.remaining(for: .passwordReset, email: "test@example.com") > 0)
        #expect(cooldown.remaining(for: .passwordReset, email: "other@example.com") == 0)
        #expect(cooldown.remaining(for: .verification, email: "test@example.com") == 0)
        cooldown.clear()
        #expect(cooldown.remaining(for: .passwordReset, email: "test@example.com") == 0)
    }
}
