public enum RunnerProvisioningProgress: Sendable, Equatable {
    case fetchingMetadata
    case verifyingBinary(filename: String)
    case registeringInstances(count: Int)
}
