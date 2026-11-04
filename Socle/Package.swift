// swift-tools-version: 6.2
import PackageDescription

// Briques communes (journal, barre de menus), embarquées pour que le dépôt se compile seul.
let package = Package(
    name: "Socle",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SocleCore", targets: ["SocleCore"]),
        .library(name: "SocleBarreDeMenus", targets: ["SocleBarreDeMenus"]),
    ],
    targets: [
        .target(name: "SocleCore"),
        .target(name: "SocleBarreDeMenus", dependencies: ["SocleCore"]),
        .testTarget(name: "SocleCoreTests", dependencies: ["SocleCore"]),
    ]
)
