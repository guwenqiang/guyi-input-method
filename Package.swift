// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "guyi",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "guyi", targets: ["GuyiApp"]), .executable(name: "guyi-eval", targets: ["GuyiEval"])],
    targets: [
        .target(name: "GuyiCore"),
        .target(name: "CRimeBridge", cSettings: [.unsafeFlags(["-I/opt/homebrew/include"])], linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib", "-lrime"])]),
        .target(name: "CInputMethodBridge", linkerSettings: [.linkedFramework("Foundation")]),
        .executableTarget(name: "GuyiApp", dependencies: ["GuyiCore", "CRimeBridge", "CInputMethodBridge"]),
        .executableTarget(name: "GuyiEval", dependencies: ["GuyiCore"]),
        .executableTarget(name: "GuyiInstaller"),
        .executableTarget(name: "GuyiCoreTests", dependencies: ["GuyiCore"], path: "Tests/GuyiCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
