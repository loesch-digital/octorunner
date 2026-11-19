import CoreModels
import SwiftUI
import UniformTypeIdentifiers

struct RunnerConsoleExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let data: Data

    init(lines: [RunnerLogLine], retaining ids: Set<Int>) {
        data = Data(Self.formattedText(from: lines, retaining: ids).utf8)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func formattedText(from lines: [RunnerLogLine], retaining ids: Set<Int>? = nil) -> String {
        return lines.compactMap { line -> String? in
            if let ids, !ids.contains(line.id) { return nil }
            return "[\(line.timestampText) \(line.level.rawValue)] \(line.message)"
        }.joined(separator: "\n")
    }
}
