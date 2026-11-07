// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OctoRunnerKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
        .library(name: "GitHubAPI", targets: ["GitHubAPI"]),
        .library(name: "RunnerEngine", targets: ["RunnerEngine"]),
        .library(name: "TelemetryKit", targets: ["TelemetryKit"]),
        .library(name: "AppShellFeature", targets: ["AppShellFeature"])
    ],
    targets: [
        .target(
            name: "CoreModels",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DesignSystem",
            dependencies: ["CoreModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SecurityKit",
            dependencies: ["CoreModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "GitHubAPI",
            dependencies: ["CoreModels", "SecurityKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RunnerEngine",
            dependencies: ["CoreModels", "SecurityKit", "GitHubAPI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TelemetryKit",
            dependencies: ["CoreModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AppShellFeature",
            dependencies: [
                "CoreModels",
                "DesignSystem",
                "SecurityKit",
                "GitHubAPI",
                "RunnerEngine",
                "TelemetryKit"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OctoRunnerKitTests",
            dependencies: [
                "CoreModels",
                "DesignSystem",
                "SecurityKit",
                "GitHubAPI",
                "RunnerEngine",
                "TelemetryKit",
                "AppShellFeature"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
