import Darwin
import Dispatch
import Foundation
import Synchronization

struct RunnerProcessLogPipe {
    let writer: Writer
    let reader: Reader

    init(console: RunnerProcessConsole, standardError: Bool) throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard pipe(&descriptors) == 0 else { throw Self.pipeError }
        var owned = false
        defer {
            if !owned { for fd in descriptors { close(fd) } }
        }
        for index in descriptors.indices {
            let fd = descriptors[index]
            if fd <= STDERR_FILENO {
                let duplicate = fcntl(fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
                guard duplicate >= 0 else { throw Self.pipeError }
                descriptors[index] = duplicate
                close(fd)
            } else if fcntl(fd, F_SETFD, FD_CLOEXEC) == -1 {
                throw Self.pipeError
            }
        }
        guard fcntl(descriptors[0], F_SETFL, O_NONBLOCK) != -1 else { throw Self.pipeError }
        writer = Writer(fd: descriptors[1])
        reader = Reader(fd: descriptors[0], console: console, standardError: standardError)
        owned = true
    }

    private static var pipeError: POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    final class Writer {
        let fd: Int32
        init(fd: Int32) { self.fd = fd }
        deinit { close(fd) }
    }

    final class Reader: Sendable {
        private let fd: Int32
        private let console: RunnerProcessConsole
        private let standardError: Bool
        private let queue = DispatchQueue(label: "io.octorunner.process-log", qos: .utility)
        private let source: any DispatchSourceRead
        private let framer = Mutex(RunnerLogByteFramer())

        init(fd: Int32, console: RunnerProcessConsole, standardError: Bool) {
            self.fd = fd
            self.console = console
            self.standardError = standardError
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.drain() }
            source.setCancelHandler { close(fd) }
            source.activate()
        }

        func finish() {
            queue.sync { drain(ending: true) }
        }

        deinit { source.cancel() }

        private func drain(ending: Bool = false) {
            guard !source.isCancelled else { return }
            var data = Data(count: 16 * 1024)
            var finished = false
            // A background process can retain the writer after the owned group exits.
            // Bound each event and the final drain so log capture never waits for it.
            for _ in 0..<32 {
                let size = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if size > 0 {
                    let output = framer.withLock { $0.append(Data(data.prefix(size))) }
                    console.record(output, standardError: standardError)
                } else if size == 0 {
                    finished = true
                    break
                } else if errno != EINTR {
                    finished = errno != EAGAIN
                    break
                }
            }
            if finished || ending {
                console.record(framer.withLock { $0.finish() }, standardError: standardError)
                source.cancel()
            }
        }
    }
}
