import Foundation

public struct RunnerLogLine: Sendable, Equatable, Identifiable {
    public let id: Int
    public let timestampText: String
    public let level: RunnerLogLevel
    public let message: String

    public init(
        id: Int,
        timestampText: String,
        level: RunnerLogLevel,
        message: String
    ) {
        self.id = id
        self.timestampText = timestampText
        self.level = level
        self.message = message
    }

    /// Parses a GitHub Actions `_diag/Runner_*.log` or `Worker_*.log` line.
    /// Example: `[2026-11-07 18:10:00Z INFO Runner] Listening for Jobs`
    public static func parse(_ rawLine: String, index: Int) -> RunnerLogLine {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        var timestamp = "--:--:--"
        var level: RunnerLogLevel = .info
        var body = trimmed

        if trimmed.hasPrefix("["), let closingBracket = trimmed.firstIndex(of: "]") {
            let header = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
            body = String(trimmed[trimmed.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
            let tokens = header.split(whereSeparator: \.isWhitespace).map(String.init)
            if tokens.count >= 2 {
                timestamp = tokens[1].replacingOccurrences(of: "Z", with: "")
            } else if let first = tokens.first {
                timestamp = first
            }
            if header.contains("ERR") || header.contains("ERROR") || header.contains("FAIL") {
                level = .error
            } else if header.contains("WARN") {
                level = .warning
            } else if body.contains("✓") || body.localizedStandardContains("succeeded") || body.localizedStandardContains("completed") {
                level = .success
            }
        } else {
            if trimmed.localizedStandardContains("error") || trimmed.localizedStandardContains("failed") {
                level = .error
            } else if trimmed.localizedStandardContains("warn") {
                level = .warning
            } else if trimmed.contains("✓") {
                level = .success
            }
        }

        return RunnerLogLine(
            id: index,
            timestampText: timestamp,
            level: level,
            message: body
        )
    }
}
