import Foundation

public struct WorkflowHistorySelection: Sendable, Hashable {
    public let accountID: Int64
    public let keychainAccountKey: String
    public let repository: String

    public init(accountID: Int64, keychainAccountKey: String, repository: String) {
        self.accountID = accountID
        self.keychainAccountKey = keychainAccountKey
        self.repository = repository
    }
}
