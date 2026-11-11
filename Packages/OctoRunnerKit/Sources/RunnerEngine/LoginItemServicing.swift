import Foundation

public protocol LoginItemServicing: Sendable {
    func status() async -> LoginItemState
    func setEnabled(_ enabled: Bool) async throws
}
