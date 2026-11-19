import Foundation

struct InstalledRunnerVersionSummary: Sendable {
    let versions: [String]
    let hasUnknownVersion: Bool
    let runnerCount: Int

    init(_ recordedVersions: [String?]) {
        let known = recordedVersions.compactMap { version -> String? in
            guard let value = version?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        versions = Set(known).sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        hasUnknownVersion = known.count < recordedVersions.count
        runnerCount = recordedVersions.count
    }
}
