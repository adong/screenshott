// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenshott",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no AppKit UI — everything here is unit-testable.
        .target(name: "ScreenshottCore"),
        .executableTarget(
            name: "Screenshott",
            dependencies: ["ScreenshottCore"]
        ),
        .testTarget(
            name: "ScreenshottCoreTests",
            dependencies: ["ScreenshottCore"]
        ),
        // Dev tool that redraws Support/AppIcon.iconset; see scripts/make-icon.sh.
        .executableTarget(name: "MakeIcon", path: "Tools/MakeIcon"),
        // Dev tool for scripts/verify-disclaim.sh: does a workflow step inherit Screen Recording?
        .executableTarget(name: "TCCProbe", path: "Tools/TCCProbe"),
    ]
)
