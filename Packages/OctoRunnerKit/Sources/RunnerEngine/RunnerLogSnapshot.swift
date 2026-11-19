import CoreModels

public struct RunnerLogSnapshot: Sendable, Equatable {
    public let lines: [RunnerLogLine]
    public let wasClipped: Bool
    public let exportLines: [RunnerLogLine]
}

struct RunnerLogBuffer {
    private let limit: Int
    private var lines: [RunnerLogLine] = []
    private var exportLines: [RunnerLogLine] = []
    private var nextID = 0
    private(set) var wasClipped = false

    init(maxLines: Int) {
        limit = min(max(maxLines, 1), 1_000)
    }

    var snapshot: RunnerLogSnapshot { .init(lines: lines, wasClipped: wasClipped, exportLines: exportLines) }

    mutating func noteClipping() {
        wasClipped = true
    }

    mutating func append(_ output: RunnerLogByteFramer.Output, standardError: Bool = false) {
        if output.discardedLineCount > 0 { noteClipping() }
        let retained = output.lines.suffix(limit)
        if retained.count < output.lines.count { noteClipping() }
        let excess = lines.count + retained.count - limit
        if excess > 0 {
            lines.removeFirst(excess)
            exportLines.removeFirst(excess)
            noteClipping()
        }
        for (text, export) in zip(retained, output.permitsExport.suffix(limit)) {
            nextID += 1
            let parsed = RunnerLogLine.parse(text, index: nextID)
            let line = standardError && parsed.level == .info
                ? RunnerLogLine(id: parsed.id, timestampText: parsed.timestampText, level: .error, message: parsed.message)
                : parsed
            lines.append(line)
            exportLines.append(export ? line
                : .init(id: line.id, timestampText: "--:--:--", level: line.level, message: "[REDACTED]"))
        }
    }
}
