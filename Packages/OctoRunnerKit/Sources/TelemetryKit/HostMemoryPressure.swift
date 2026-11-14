/// Dispatch pressure flags returned by kern.memorystatus_vm_pressure_level.
/// Unknown values remain unavailable; these are not XNU's internal pressure levels.
public enum HostMemoryPressure: Int32, Sendable, Equatable {
    case normal = 1
    case warning = 2
    case critical = 4
}
