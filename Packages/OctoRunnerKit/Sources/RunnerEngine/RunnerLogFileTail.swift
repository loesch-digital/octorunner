import Darwin
import Dispatch
import Foundation

public enum RunnerFileLogSource: Sendable {
    case diagnostics
    case launchAgent
}

struct RunnerLogFileTail {
    private let source: RunnerFileLogSource
    private let notifications: AsyncStream<Void>.Continuation
    private var root: WatchedDescriptor?
    private var directory: WatchedDescriptor?
    private var files: [LogFileCursor] = []
    private var rotated: [LogFileCursor] = []
    private var buffer: RunnerLogBuffer

    init(rootURL: URL, source: RunnerFileLogSource, maxLines: Int,
         notifications: AsyncStream<Void>.Continuation) {
        self.source = source
        self.notifications = notifications
        buffer = RunnerLogBuffer(maxLines: maxLines)
        if rootURL.isFileURL {
            root = WatchedDescriptor(
                fd: open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC),
                notifications: notifications)
        }
    }

    var canFollow: Bool { root != nil }

    mutating func scan() -> RunnerLogSnapshot {
        guard let root else { return buffer.snapshot }
        refreshDirectory(from: root.fd)
        var active: [LogFileCursor] = []
        if let directory {
            let names = switch source {
            case .launchAgent: ["launchd.stdout.log", "launchd.stderr.log"]
            case .diagnostics: Self.diagnosticNames(in: directory.fd)
            }
            for name in names {
                if let cursor = openFile(directoryFD: directory.fd, name: name) {
                    active.append(cursor)
                }
            }
        }
        retireReplacedFiles()
        files = active
        for index in rotated.indices { rotated[index].read(into: &buffer) }
        for index in files.indices { files[index].read(into: &buffer) }
        return buffer.snapshot
    }

    private mutating func openFile(directoryFD: Int32, name: String) -> LogFileCursor? {
        var attributes = stat()
        guard fstatat(directoryFD, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0,
              attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1 else { return nil }
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_nlink == 1 else {
            close(fd)
            return nil
        }
        if let index = files.firstIndex(where: { $0.watcher.identity.matches(attributes) }) {
            close(fd)
            return files.remove(at: index)
        }
        if let index = rotated.firstIndex(where: { $0.watcher.identity.matches(attributes) }) {
            close(fd)
            return rotated.remove(at: index)
        }
        guard let watcher = WatchedDescriptor(fd: fd, notifications: notifications) else { return nil }
        return LogFileCursor(watcher: watcher, name: name, standardError: name == "launchd.stderr.log")
    }

    private mutating func refreshDirectory(from rootFD: Int32) {
        let fd = openat(rootFD, "_diag", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            directory = nil
            return
        }
        var attributes = stat()
        if fstat(fd, &attributes) == 0, directory?.identity.matches(attributes) == true {
            close(fd)
        } else {
            directory = WatchedDescriptor(fd: fd, notifications: notifications)
        }
    }

    private mutating func retireReplacedFiles() {
        for var cursor in files {
            if source == .launchAgent {
                // A running service retains its opened stdout/stderr after rename.
                // Keep at most one replaced inode per output channel.
                if let index = rotated.firstIndex(where: { $0.name == cursor.name }) {
                    var previous = rotated.remove(at: index)
                    previous.read(into: &buffer)
                    previous.finish(into: &buffer)
                    buffer.noteClipping()
                }
                rotated.append(cursor)
            } else {
                cursor.read(into: &buffer)
                cursor.finish(into: &buffer)
            }
        }
        files.removeAll()
    }

    private static func diagnosticNames(in directoryFD: Int32) -> [String] {
        let fd = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        guard let stream = fdopendir(fd) else {
            close(fd)
            return []
        }
        defer { closedir(stream) }
        var newestRunner: String?
        var newestWorker: String?
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: &entry.pointee.d_name) {
                String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            guard name.hasSuffix(".log"), name.hasPrefix("Runner_") || name.hasPrefix("Worker_") else { continue }
            var attributes = stat()
            guard fstatat(directoryFD, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0,
                  attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1 else { continue }
            if name.hasPrefix("Runner_"), name > (newestRunner ?? "") { newestRunner = name }
            if name.hasPrefix("Worker_"), name > (newestWorker ?? "") { newestWorker = name }
        }
        return [newestRunner, newestWorker].compactMap { $0 }
    }
}

private struct FileIdentity {
    let device: dev_t
    let inode: ino_t

    func matches(_ attributes: stat) -> Bool {
        device == attributes.st_dev && inode == attributes.st_ino
    }
}

private final class WatchedDescriptor {
    let fd: Int32
    let identity: FileIdentity
    private let watch: any DispatchSourceFileSystemObject

    init?(fd: Int32, notifications: AsyncStream<Void>.Continuation) {
        guard fd >= 0 else { return nil }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0 else {
            close(fd)
            return nil
        }
        self.fd = fd
        identity = .init(device: attributes.st_dev, inode: attributes.st_ino)
        watch = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .revoke, .attrib], queue: .global(qos: .utility))
        watch.setEventHandler { notifications.yield(()) }
        watch.setCancelHandler { close(fd) }
        watch.activate()
    }

    deinit { watch.cancel() }
}

private struct LogFileCursor {
    let watcher: WatchedDescriptor
    let name: String
    let standardError: Bool
    private var offset: off_t = 0
    private var anchor = Data()
    private var framer = RunnerLogByteFramer()
    private var skippingPartialLine = false

    init(watcher: WatchedDescriptor, name: String, standardError: Bool) {
        self.watcher = watcher
        self.name = name
        self.standardError = standardError
    }

    mutating func read(into buffer: inout RunnerLogBuffer) {
        var attributes = stat()
        guard fstat(watcher.fd, &attributes) == 0 else { return }
        let size = attributes.st_size
        if size < offset || (!anchor.isEmpty && readBytes(count: anchor.count, at: offset - off_t(anchor.count)) != anchor) {
            offset = 0
            anchor = Data()
            framer = RunnerLogByteFramer()
            skippingPartialLine = false
        }
        let maximumBytes: off_t = 256 * 1024
        if size - offset > maximumBytes {
            buffer.noteClipping()
            offset = size - maximumBytes
            framer = RunnerLogByteFramer()
            framer.markExportContextUnknown()
            skippingPartialLine = readBytes(count: 1, at: offset - 1).first != 0x0A
        }
        while offset < size, !Task.isCancelled {
            let bytes = readBytes(count: Int(min(size - offset, 16 * 1024)), at: offset)
            guard !bytes.isEmpty else { break }
            offset += off_t(bytes.count)
            anchor = Data(bytes.suffix(64))
            if skippingPartialLine {
                guard let separator = bytes.firstIndex(of: 0x0A) else { continue }
                skippingPartialLine = false
                buffer.append(framer.append(bytes.suffix(from: bytes.index(after: separator))), standardError: standardError)
            } else {
                buffer.append(framer.append(bytes), standardError: standardError)
            }
        }
    }

    mutating func finish(into buffer: inout RunnerLogBuffer) {
        buffer.append(framer.finish(), standardError: standardError)
    }

    private func readBytes(count: Int, at offset: off_t) -> Data {
        var bytes = Data(count: count)
        let result = bytes.withUnsafeMutableBytes { destination in
            pread(watcher.fd, destination.baseAddress, count, offset)
        }
        guard result > 0 else { return Data() }
        return Data(bytes.prefix(result))
    }
}
