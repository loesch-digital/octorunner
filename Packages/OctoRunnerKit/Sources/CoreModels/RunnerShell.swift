import Foundation

public enum RunnerShell: String, CaseIterable, Codable, Sendable, Identifiable {
    case bash = "/bin/bash"
    case zsh = "/bin/zsh"
    case homebrewBash = "/opt/homebrew/bin/bash"

    public var id: String { rawValue }
}
