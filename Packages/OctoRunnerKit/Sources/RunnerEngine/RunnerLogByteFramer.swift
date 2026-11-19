import Foundation

struct RunnerLogByteFramer {
    struct Output {
        var lines: [String] = []
        var permitsExport: [Bool] = []
        var discardedLineCount = 0
    }

    private let maximumLineBytes: Int
    private var line: [UInt8] = []
    private var discardingLine = false
    private var redactor = RunnerLogRedactor()

    init(maximumLineBytes: Int = 16 * 1024) {
        self.maximumLineBytes = max(1, maximumLineBytes)
    }

    mutating func append(_ bytes: Data) -> Output {
        var output = Output()
        for byte in bytes {
            if byte == 0x0A {
                endLine(into: &output)
            } else if !discardingLine {
                if line.count < maximumLineBytes || (line.count == maximumLineBytes && byte == 0x0D) {
                    line.append(byte)
                } else {
                    line.removeAll(keepingCapacity: true)
                    discardingLine = true
                    markExportContextUnknown()
                    output.discardedLineCount += 1
                }
            }
        }
        return output
    }

    mutating func finish() -> Output {
        var output = Output()
        endLine(into: &output)
        return output
    }

    mutating func markExportContextUnknown() {
        redactor.markContextUnknown()
    }

    private mutating func endLine(into output: inout Output) {
        if !discardingLine {
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty {
                let decoded = String(decoding: line, as: UTF8.self)
                output.lines.append(decoded)
                output.permitsExport.append(redactor.permitsExport(decoded))
            }
        }
        line.removeAll(keepingCapacity: true)
        discardingLine = false
    }
}
