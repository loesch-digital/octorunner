import Darwin
import Foundation

public struct SystemHostTelemetrySampler: HostTelemetrySampling {
    public init() {}

    public func sample() -> HostTelemetrySample {
        let info = ProcessInfo.processInfo
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info_data_t()
        let cpuCapacity = MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        var cpuCount = mach_msg_type_number_t(cpuCapacity)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: cpuCapacity) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        let ticks: HostCPUTicks? = cpuResult == KERN_SUCCESS ? HostCPUTicks(
            user: UInt64(cpu.cpu_ticks.0), system: UInt64(cpu.cpu_ticks.1),
            idle: UInt64(cpu.cpu_ticks.2), nice: UInt64(cpu.cpu_ticks.3)) : nil

        var vm = vm_statistics64_data_t()
        let vmCapacity = MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        var vmCount = mach_msg_type_number_t(vmCapacity)
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: vmCapacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        let memory: HostVMStatistics? = pageResult == KERN_SUCCESS && vmResult == KERN_SUCCESS ? HostVMStatistics(
            pageSize: UInt64(pageSize), anonymousPages: UInt64(vm.internal_page_count),
            wiredPages: UInt64(vm.wire_count), compressedPages: UInt64(vm.compressor_page_count),
            purgeablePages: UInt64(vm.purgeable_count)) : nil

        var performance: Int?
        var efficiency: Int?
        var clusters: [HostCPUCluster] = []
        // Level names avoid assuming any CPU-index to core-type mapping.
        for level in 0..<min(Self.readInt("hw.nperflevels") ?? 0, 8) {
            let prefix = "hw.perflevel\(level)"
            guard let name = Self.readString("\(prefix).name"),
                  let count = Self.readInt("\(prefix).physicalcpu") else { continue }
            clusters.append(HostCPUCluster(id: level, name: name, physicalCoreCount: count))
            if name.lowercased() == "performance" { performance = count }
            if name.lowercased() == "efficiency" { efficiency = count }
        }
        return HostTelemetrySample(cpuSummary: Self.readString("machdep.cpu.brand_string") ?? "Unknown processor",
            totalCoreCount: info.processorCount, physicalMemoryBytes: info.physicalMemory,
            osVersionString: info.operatingSystemVersionString, cpuTicks: ticks, vmStatistics: memory,
            performanceCoreCount: performance, efficiencyCoreCount: efficiency, coreClusters: clusters)
    }

    private static func readInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    private static func readString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size <= 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
