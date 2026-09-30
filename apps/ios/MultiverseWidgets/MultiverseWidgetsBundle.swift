import WidgetKit
import SwiftUI

@main
struct MultiverseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UniversePercentWidget()
        NextInOrderWidget()
        DuelOfDayWidget()
        PremiereLiveActivity()
    }
}

// MARK: - Timeline compartilhada

struct SnapshotEntry: WidgetKit.TimelineEntry {
    let date: Date
    let snapshot: WidgetBridge.Snapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetBridge.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetBridge.load())
        // O app atualiza os widgets sob demanda (`WidgetBridge.Session.save` chama `reloadAllTimelines`),
        // então essa próxima entrada é só uma rede de segurança.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}
