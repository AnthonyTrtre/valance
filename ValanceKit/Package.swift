// swift-tools-version: 6.2
import PackageDescription

// ValanceKit : la logique pure de Valance (Foundation seule, testable sous Linux par `swift test`).
// - ValanceCoeur : géométrie de la barre, longueur du séparateur, encoche, plusieurs écrans, machine à états
//   masqué / révélé / repli, raccourcis, réglages, inventaire (appariement fenêtres ↔ Accessibilité), règles,
//   empreintes d'images, disjoncteur et échéance des appels lents, mise en page de la barre secondaire.
// Tout ce qui touche AppKit, Carbon, l'Accessibilité ou ScreenCaptureKit vit dans la coque d'app (`../Sources`).
// Aucune dépendance tierce.
let package = Package(
    name: "ValanceKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ValanceCoeur", targets: ["ValanceCoeur"]),
    ],
    targets: [
        .target(name: "ValanceCoeur"),
        .testTarget(name: "ValanceCoeurTests", dependencies: ["ValanceCoeur"]),
    ],
    swiftLanguageModes: [.v6]
)
