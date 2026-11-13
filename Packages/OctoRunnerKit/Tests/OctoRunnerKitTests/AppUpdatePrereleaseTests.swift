import Foundation
@testable import GitHubAPI
import Testing

struct AppUpdatePrereleaseTests {
    @Test("The beta keeps its release identity while standard bundle fields remain numeric")
    func bundleReleaseIdentity() {
        #expect(AppUpdaterActor.bundleReleaseVersion(shortVersion: "0.5.0", releaseVersion: "0.5.0-beta.1") == "0.5.0-beta.1")
        #expect(AppUpdaterActor.bundleReleaseVersion(shortVersion: "0.5.0", releaseVersion: nil) == "0.5.0")
        #expect(AppUpdaterActor.bundleReleaseVersion(shortVersion: "0.5.0", releaseVersion: "invalid") == "0.5.0")
        #expect(AppUpdaterActor.bundleReleaseVersion(shortVersion: nil, releaseVersion: nil) == "0.0.0")
        #expect(AppUpdaterActor.bundleReleaseVersion(shortVersion: "invalid", releaseVersion: nil) == "0.0.0")
    }

    @Test("Updates follow SemVer prerelease precedence rather than numeric fragments")
    func prereleaseOrdering() {
        let ordered = ["0.5.0-alpha", "0.5.0-alpha.1", "0.5.0-alpha.beta", "0.5.0-beta", "0.5.0-beta.2", "0.5.0-beta.11", "0.5.0-rc.1", "0.5.0"]
        for (index, candidate) in ordered.enumerated() {
            for (currentIndex, current) in ordered.enumerated() {
                #expect(AppUpdaterActor.isVersion(candidate, newerThan: current) == (index > currentIndex), "\(candidate) vs \(current)")
            }
        }
        #expect(AppUpdaterActor.isVersion("v0.5.0", newerThan: "0.5.0-beta.1"))
        #expect(!AppUpdaterActor.isVersion("0.4.4", newerThan: "0.5.0-beta.1"))
        #expect(!AppUpdaterActor.isVersion("0.5.0+build.2", newerThan: "0.5.0+build.1"))
        #expect(AppUpdaterActor.isVersion("0.5.0-beta.999999999999999999999999999999", newerThan: "0.5.0-beta.10"))
    }

    @Test("Malformed release versions never offer updates")
    func invalidVersionsAreRejected() {
        for invalid in ["", "0.5", "01.5.0", "0.5.0-beta.01", "0.5.0-", "0.5.0+", "0.5.0-β", "0.5.0.1", "vv0.5.0"] {
            #expect(!AppUpdaterActor.isVersion(invalid, newerThan: "0.4.4"), "\(invalid)")
            #expect(!AppUpdaterActor.isVersion("0.6.0", newerThan: invalid), "\(invalid)")
        }
    }
}
