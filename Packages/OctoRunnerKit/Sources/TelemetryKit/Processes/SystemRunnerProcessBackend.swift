import Darwin
import Foundation

/// Uses libproc metadata only: no command arguments, environment, task_for_pid or file traversal.
public struct SystemRunnerProcessBackend: RunnerProcessBackend {
    public init() {}

    public func sample() throws -> RunnerProcessSample {
        try Task.checkCancellation()
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), geteuid(), nil, 0)
        guard bytes > 0 else { throw RunnerProcessError.unavailable }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.stride + 256)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_UID_ONLY), geteuid(), buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0, Int(count) <= pids.count * MemoryLayout<Int32>.stride else { throw RunnerProcessError.unavailable }
        var processes: [RunnerProcessMetadata] = []
        for pid in pids.prefix(Int(count) / MemoryLayout<Int32>.stride) where pid > 1 {
            try Task.checkCancellation()
            if let process = metadata(pid: pid) { processes.append(process) }
        }
        return RunnerProcessSample(uptime: ProcessInfo.processInfo.systemUptime, sampledAt: .now, processes: processes)
    }

    public func requestTermination(of process: RunnerProcessMetadata) throws {
        try Task.checkCancellation()
        guard process.identity.pid > 1, process.identity.pid != getpid(), process.userID == geteuid(),
              let fresh = metadata(pid: process.identity.pid), fresh.hasSameIdentityAndLocation(as: process) else {
            throw RunnerProcessError.changedOrUnattributed
        }
        try Task.checkCancellation()
        guard kill(process.identity.pid, SIGTERM) == 0 else { throw RunnerProcessError.signalFailed(errno) }
    }

    private func metadata(pid: Int32) -> RunnerProcessMetadata? {
        guard let before = bsdInfo(pid), before.pbi_uid == geteuid() else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = path.withUnsafeMutableBytes { buffer in proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count)) }
        guard length > 0, let zero = path.firstIndex(of: 0) else { return nil }
        let executable = String(decoding: path[..<zero].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var task = proc_taskinfo()
        let taskSize = MemoryLayout<proc_taskinfo>.size
        let hasStats = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(taskSize)) == taskSize
        guard let after = bsdInfo(pid), before.pbi_pid == after.pbi_pid,
              before.pbi_start_tvsec == after.pbi_start_tvsec, before.pbi_start_tvusec == after.pbi_start_tvusec,
              before.pbi_uid == after.pbi_uid, before.pbi_ppid == after.pbi_ppid else { return nil }
        var timebase = mach_timebase_info_data_t()
        let hasTimebase = mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.denom > 0
        let cpu = hasStats && hasTimebase ? (Double(task.pti_total_user) + Double(task.pti_total_system)) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000 : nil
        return RunnerProcessMetadata(identity: ProcessIdentity(pid: pid, startSeconds: after.pbi_start_tvsec, startMicroseconds: after.pbi_start_tvusec),
            parentPID: Int32(after.pbi_ppid), userID: after.pbi_uid, executablePath: executable,
            cpuTimeSeconds: cpu, residentBytes: hasStats ? task.pti_resident_size : nil)
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size ? info : nil
    }
}
