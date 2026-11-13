import TelemetryKit

struct TelemetrySamplingRequest: Equatable {
    let interval: Int
    let refreshID: Int
    let targets: [RunnerProcessTarget]
}
