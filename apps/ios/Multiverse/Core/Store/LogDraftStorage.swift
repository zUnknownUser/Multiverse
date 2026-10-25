import CryptoKit
import Foundation

@MainActor protocol LogDraftStorage {
    func load() throws -> LogDraft?
    func save(_ draft: LogDraft?) throws
}

/// One private draft per account and deployment. Never included in device backups.
@MainActor final class FileLogDraftStorage: LogDraftStorage {
    let file: URL

    init(userID: String, environment: AppEnvironment = .current, directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let identity = Data("\(environment.rawValue):\(userID)".utf8)
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        file = root.appendingPathComponent("DiaryDrafts", isDirectory: true).appendingPathComponent(key + ".json")
    }

    func load() throws -> LogDraft? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(LogDraft.self, from: Data(contentsOf: file))
    }

    func save(_ draft: LogDraft?) throws {
        guard let draft else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic, .completeFileProtection])
    }
}
