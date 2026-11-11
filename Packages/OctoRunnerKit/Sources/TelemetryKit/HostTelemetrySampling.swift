public protocol HostTelemetrySampling: Sendable {
    func sample() -> HostTelemetrySample
}
