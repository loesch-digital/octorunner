import Foundation
import SwiftData

public enum OctoRunnerPersistence {
    public static var defaultStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        let dir = appSupport.appending(path: "io.octorunner.macos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dedicatedStore = dir.appending(path: "octorunner.store")
        let legacyDefaultStore = appSupport.appending(path: "default.store")

        // If the dedicated store doesn't exist yet, copy over any existing v0.2.x default.store so the user's account is preserved
        if !FileManager.default.fileExists(atPath: dedicatedStore.path()),
           FileManager.default.fileExists(atPath: legacyDefaultStore.path()) {
            try? FileManager.default.copyItem(at: legacyDefaultStore, to: dedicatedStore)
        }
        return dedicatedStore
    }

    public static func makeSharedContainer(storeURL: URL? = nil) -> ModelContainer {
        let targetURL = storeURL ?? defaultStoreURL
        let schema = Schema([
            RunnerEntity.self,
            JobRunEntity.self,
            GitHubAccountEntity.self
        ])

        let diskConfig = ModelConfiguration(schema: schema, url: targetURL)
        if let container = try? ModelContainer(for: schema, configurations: [diskConfig]) {
            return container
        }

        // Self-heal: remove incompatible or corrupted SQLite store files (.store, .store-shm, .store-wal) and recreate cleanly
        removeStoreFiles(at: targetURL)

        if let healedContainer = try? ModelContainer(for: schema, configurations: [diskConfig]) {
            return healedContainer
        }

        // Last resort fallback: in-memory container (never fatalError)
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [memoryConfig])
    }

    private static func removeStoreFiles(at storeURL: URL) {
        let basePath = storeURL.path()
        for suffix in ["", "-shm", "-wal"] {
            let fileURL = URL(fileURLWithPath: basePath + suffix)
            if FileManager.default.fileExists(atPath: fileURL.path()) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
