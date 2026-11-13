public protocol VolumeCapacitySampling: Sendable {
    func sample() async -> VolumeCapacitySnapshot?
}
