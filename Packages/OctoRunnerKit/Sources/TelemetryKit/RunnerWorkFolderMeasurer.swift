import Foundation

/// Measures the logical sizes of regular files within a requested work folder.
public actor RunnerWorkFolderMeasurer {
    public init() {}

    public func measure(path: String) throws -> Int64 {
        try Task.checkCancellation()
        guard path.hasPrefix("/") else { throw CocoaError(.fileReadInvalidFileName) }
        let root = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
        guard root.path(percentEncoded: false) != "/" else { throw CocoaError(.fileReadInvalidFileName) }

        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink == false else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var traversalError: (any Error)?
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else { throw CocoaError(.fileReadUnknown) }

        var bytes: Int64 = 0
        for case let file as URL in files {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                files.skipDescendants()
                continue
            }
            guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else { continue }
            let (sum, overflow) = bytes.addingReportingOverflow(Int64(size))
            guard !overflow else { throw CocoaError(.fileReadTooLarge) }
            bytes = sum
        }
        try Task.checkCancellation()
        if let traversalError { throw traversalError }
        return bytes
    }
}
