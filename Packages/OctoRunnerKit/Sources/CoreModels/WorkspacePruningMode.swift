import Foundation

public enum WorkspacePruningMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case manual
    case olderThanDays
    case lowDiskSpace

    public var id: String { rawValue }
}
