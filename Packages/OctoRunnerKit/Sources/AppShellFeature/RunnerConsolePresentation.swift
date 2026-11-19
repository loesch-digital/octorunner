import CoreModels
import RunnerEngine

struct RunnerConsolePresentation {
    private var latest: RunnerLogSnapshot?
    private var clearedThrough = 0
    private(set) var exportContext: [RunnerLogLine] = []
    private(set) var lines: [RunnerLogLine] = []
    private(set) var isPaused = false
    private(set) var wasClipped = false

    mutating func receive(_ snapshot: RunnerLogSnapshot) {
        latest = snapshot
        if !isPaused { showLatest() }
    }

    mutating func togglePause() {
        isPaused.toggle()
        if !isPaused { showLatest() }
    }

    mutating func clear() {
        if let newest = latest?.lines.last?.id { clearedThrough = newest }
        lines.removeAll()
        wasClipped = false
    }

    private mutating func showLatest() {
        guard let latest else { return }
        exportContext = latest.exportLines
        lines = latest.lines.filter { $0.id > clearedThrough }
        wasClipped = latest.wasClipped
    }
}
