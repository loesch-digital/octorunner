/// SemVer precedence without integer overflow; build metadata does not affect ordering.
struct ReleaseVersion: Comparable {
    let core: [String]
    private let prerelease: [String]?

    init?(_ value: String) {
        let metadata = value.split(separator: "+", omittingEmptySubsequences: false)
        guard metadata.count <= 2,
              metadata.count == 1 || Self.identifiersAreValid(String(metadata[1]), prerelease: false) else { return nil }
        let parts = metadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard numbers.count == 3, numbers.allSatisfy(Self.isCanonicalNumber) else { return nil }
        if parts.count == 2 {
            guard Self.identifiersAreValid(String(parts[1]), prerelease: true) else { return nil }
            prerelease = parts[1].split(separator: ".").map(String.init)
        } else {
            prerelease = nil
        }
        core = numbers
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isCanonicalNumber(_ value: String) -> Bool {
        isDigits(value) && (value.count == 1 || !value.hasPrefix("0"))
    }

    private static func identifiersAreValid(_ value: String, prerelease: Bool) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            } && (!prerelease || !isDigits(String(part)) || isCanonicalNumber(String(part)))
        }
    }

    private static func numberIsLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.core, rhs.core) where left != right {
            return numberIsLess(left, right)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, _): return false
        case (.some, nil): return true
        case let (.some(left), .some(right)):
            for (a, b) in zip(left, right) where a != b {
                let aNumber = isDigits(a)
                let bNumber = isDigits(b)
                if aNumber && bNumber { return numberIsLess(a, b) }
                if aNumber != bNumber { return aNumber }
                return a < b
            }
            return left.count < right.count
        }
    }
}
