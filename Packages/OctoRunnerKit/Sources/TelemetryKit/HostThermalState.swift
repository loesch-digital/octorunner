/// System thermal conditions reported by ProcessInfo, independent of memory pressure.
public enum HostThermalState: Int, Sendable, Equatable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3
}
