import CoreModels
import Foundation

public struct ManagedRunnerConfiguration: Sendable, Equatable {
    public let runnerID: UUID
    public let name: String
    public let rootDirectory: URL
    public let mode: RunnerExecutionMode
    public let launch: RunnerLaunchConfiguration

    public init(runnerID: UUID, name: String, rootDirectory: URL, mode: RunnerExecutionMode,
                launch: RunnerLaunchConfiguration = RunnerLaunchConfiguration()) {
        self.runnerID = runnerID; self.name = name; self.rootDirectory = rootDirectory
        self.mode = mode; self.launch = launch
    }
}
