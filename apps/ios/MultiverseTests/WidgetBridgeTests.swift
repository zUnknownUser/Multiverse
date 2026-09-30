import Foundation
import Testing
@testable import Multiverse

@MainActor
final class WidgetSnapshotSpy: WidgetSnapshotWriting {
    var snapshots: [WidgetBridge.Snapshot] = []
    func save(_ snapshot: WidgetBridge.Snapshot) { snapshots.append(snapshot) }
}

@MainActor
struct WidgetBridgeTests {
    private let snapshot = WidgetBridge.Snapshot(
        universeName: "Universe A", universePercent: 50, universePercentDelta: 0,
        nextOrderItemTitle: "Next item", nextOrderDone: 1, nextOrderTotal: 2,
        duelQuestion: "Question", duelSideATitle: "A", duelSideBTitle: "B", duelVotesLabel: "10"
    )

    @Test func logoutClearsSnapshotAndRejectsLateWrites() throws {
        try withStorage { defaults in
            var reloads = 0
            let sessionCandidate = WidgetBridge.beginSession(defaults: defaults, reload: { reloads += 1 })
            let session = try #require(sessionCandidate)
            #expect(WidgetBridge.load(defaults: defaults) == nil)
            session.save(snapshot)
            #expect(WidgetBridge.load(defaults: defaults) == snapshot)
            WidgetBridge.clear(defaults: defaults, reload: { reloads += 1 })
            #expect(WidgetBridge.load(defaults: defaults) == nil)
            session.save(snapshot)
            #expect(WidgetBridge.load(defaults: defaults) == nil)
            #expect(reloads == 3)
        }
    }

    @Test func replacingSessionInvalidatesPreviousWriter() throws {
        try withStorage { defaults in
            let firstCandidate = WidgetBridge.beginSession(defaults: defaults, reload: {})
            let first = try #require(firstCandidate)
            first.save(snapshot)
            let secondCandidate = WidgetBridge.beginSession(defaults: defaults, reload: {})
            let second = try #require(secondCandidate)
            #expect(WidgetBridge.load(defaults: defaults) == nil)
            first.save(snapshot)
            #expect(WidgetBridge.load(defaults: defaults) == nil)
            var replacement = snapshot
            replacement.universeName = "Universe B"
            second.save(replacement)
            first.save(snapshot)
            #expect(WidgetBridge.load(defaults: defaults) == replacement)
        }
    }

    @Test func legacySnapshotWithoutSessionIsNotDisplayed() throws {
        try withStorage { defaults in
            defaults.set(try JSONEncoder().encode(snapshot), forKey: "widget-snapshot")
            #expect(WidgetBridge.load(defaults: defaults) == nil)
            let sessionCandidate = WidgetBridge.beginSession(defaults: defaults, reload: {})
            let session = try #require(sessionCandidate)
            session.save(snapshot)
            #expect(WidgetBridge.load(defaults: defaults) == snapshot)
        }
    }

    @Test func storePublishesLoadedDataAndReadingOrderChanges() async throws {
        let writer = WidgetSnapshotSpy()
        let store = AppStore(repository: MockRepository(startFollowing: false), widgetWriter: writer)
        store.syncWidgetData()
        #expect(writer.snapshots.isEmpty)
        await store.bootstrap()
        #expect(writer.snapshots.count == 1)
        let order = try #require(store.readingOrders.last)
        store.orderFollows = []
        store.toggleOrderFollow(order.id)
        #expect(writer.snapshots.count == 2)
        let progress = store.orderProgress(order)
        #expect(writer.snapshots.last?.nextOrderDone == progress.done)
        #expect(writer.snapshots.last?.nextOrderTotal == progress.total)
        let expectedTitle = order.steps.first { !store.isSeen($0) }.flatMap { store.item($0)?.title } ?? order.title
        #expect(writer.snapshots.last?.nextOrderItemTitle == expectedTitle)
    }

    @Test(arguments: ["diary", "shield"]) func markingSeenThroughOtherFlowsUpdatesReadingOrderWidget(action: String) async throws {
        let writer = WidgetSnapshotSpy()
        let session = AuthSession(userID: UUID().uuidString, email: "test@example.com", handle: "@test")
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(session.userID)") }
        let repository = MockRepository(startFollowing: false, session: session)
        let store = AppStore(repository: repository, session: session, widgetWriter: writer)
        await store.bootstrap()
        let order = try #require(store.readingOrders.first)
        store.toggleOrderFollow(order.id)
        let itemID = try #require(order.steps.first { !store.isSeen($0) && store.item($0) != nil })
        let before = try #require(writer.snapshots.last)
        let writeCount = writer.snapshots.count
        if action == "diary" {
            store.openLog(for: itemID)
            store.logDraft?.rating = 4
            store.saveLog()
            #expect(store.diary.first?.itemId == itemID)
            #expect(store.diary.first?.rating == 4)
            #expect(store.logDraft == nil)
        } else {
            store.shieldMarkSeen(itemID)
            if let item = store.item(itemID), let index = store.timelineIndex(for: item) {
                #expect(store.shieldPoints[item.uni] == index)
            }
        }
        #expect(store.isSeen(itemID))
        #expect(writer.snapshots.count == writeCount + 1)
        #expect(writer.snapshots.last?.nextOrderDone == before.nextOrderDone + 1)
        let nextTitle = order.steps.first { !store.isSeen($0) }.flatMap { store.item($0)?.title } ?? order.title
        #expect(writer.snapshots.last?.nextOrderItemTitle == nextTitle)
        let persisted = try await repository.fetchItemToggles()
        #expect(persisted.seenOverrides[itemID] == true)
    }

    @Test func cancelledLoadDoesNotPublishWidgets() async {
        let writer = WidgetSnapshotSpy()
        let store = AppStore(widgetWriter: writer)
        let task = Task { await store.bootstrap() }
        task.cancel()
        await task.value
        #expect(writer.snapshots.isEmpty)
    }

    private func withStorage(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "WidgetBridgeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
