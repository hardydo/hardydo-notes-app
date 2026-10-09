// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HardydoNotes",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark", branch: "gfm"),
    ],
    targets: [
        .target(
            name: "HardydoNotesCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .executableTarget(name: "HardydoNotes", dependencies: ["HardydoNotesCore"]),
        .testTarget(name: "HardydoNotesCoreTests", dependencies: ["HardydoNotesCore"]),
    ]
)
