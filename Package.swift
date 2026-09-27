// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "R3DsTextUI",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "TextUI", targets: ["TextUI"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3")
    ],
    targets: [
        .target(name: "TextUICore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "TextUI", dependencies: ["TextUICore"]),
        .testTarget(name: "TextUICoreTests", dependencies: ["TextUICore"]),
        .testTarget(name: "TextUIEditorTests", dependencies: ["TextUI", "TextUICore"])
    ],
    swiftLanguageModes: [.v5]
)
