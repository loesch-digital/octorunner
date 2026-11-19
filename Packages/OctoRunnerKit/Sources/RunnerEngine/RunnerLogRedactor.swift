import Foundation

struct RunnerLogRedactor {
    private static let credential = try! NSRegularExpression(
        pattern: #"(?i)\b(?:gh[pousr]_|github_pat_|AKIA[A-Z0-9]{16})|\b(?:Bearer|Basic)\s+\S+|://[^\s/@]+:[^\s/@]+@|(?:token|secret|password|authorization|api[_ -]?key|credential)[\w-]{0,64}["']?\s*[:=]|--[\w-]{0,64}(?:token|secret|password|api[_-]?key)[\w-]{0,64}\s|[\x00-\x08\x0b-\x1f\x7f]"#
    )

    private var withholdUntilKeyBoundary = false

    mutating func markContextUnknown() {
        withholdUntilKeyBoundary = true
    }

    mutating func permitsExport(_ text: String) -> Bool {
        if text.contains("PRIVATE KEY-----") {
            if text.contains("-----END") {
                withholdUntilKeyBoundary = false
                return false
            }
            if text.contains("-----BEGIN") {
                withholdUntilKeyBoundary = true
                return false
            }
        }
        guard !withholdUntilKeyBoundary else { return false }
        return Self.credential.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil
    }
}
