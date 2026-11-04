import Foundation

/// Rectangle en points, indépendant de CoreGraphics (testable sous Linux).
/// Deux repères coexistent sur macOS :
/// - **Cocoa** (`NSScreen.frame`, `NSWindow.frame`) : origine en bas à gauche de l'écran principal, y vers le haut ;
/// - **Quartz** (`CGWindowListCopyWindowInfo`, Accessibilité, ScreenCaptureKit) : origine en haut à gauche, y vers le bas.
/// Les fonctions ci-dessous disent toujours dans quel repère elles travaillent.
public struct Cadre: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var largeur: Double
    public var hauteur: Double

    public init(x: Double, y: Double, largeur: Double, hauteur: Double) {
        self.x = x
        self.y = y
        self.largeur = largeur
        self.hauteur = hauteur
    }

    public static let zero = Cadre(x: 0, y: 0, largeur: 0, hauteur: 0)

    public var minX: Double { x }
    public var maxX: Double { x + largeur }
    public var minY: Double { y }
    public var maxY: Double { y + hauteur }
    public var milieuX: Double { x + largeur / 2 }
    public var milieuY: Double { y + hauteur / 2 }
    public var aire: Double { max(0, largeur) * max(0, hauteur) }
    public var estVide: Bool { largeur <= 0 || hauteur <= 0 }

    public func contient(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    public func intersection(_ autre: Cadre) -> Cadre? {
        let x0 = max(minX, autre.minX), x1 = min(maxX, autre.maxX)
        let y0 = max(minY, autre.minY), y1 = min(maxY, autre.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return Cadre(x: x0, y: y0, largeur: x1 - x0, hauteur: y1 - y0)
    }

    /// Chevauchement horizontal seul (en points), utile pour l'encoche et les sections.
    public func recouvrementHorizontal(_ autre: Cadre) -> Double {
        max(0, min(maxX, autre.maxX) - max(minX, autre.minX))
    }

    /// Intersection sur union (0 à 1) : mesure de ressemblance de deux cadres.
    public func iou(_ autre: Cadre) -> Double {
        guard let inter = intersection(autre) else { return 0 }
        let union = aire + autre.aire - inter.aire
        return union > 0 ? inter.aire / union : 0
    }

    /// Part du plus petit des deux cadres couverte par l'autre (0 à 1) : 1 quand l'un contient l'autre.
    public func contenance(_ autre: Cadre) -> Double {
        guard let inter = intersection(autre), min(aire, autre.aire) > 0 else { return 0 }
        return inter.aire / min(aire, autre.aire)
    }

    public func decale(dx: Double = 0, dy: Double = 0) -> Cadre {
        Cadre(x: x + dx, y: y + dy, largeur: largeur, hauteur: hauteur)
    }

    public var description: String {
        "(\(Self.f(x)), \(Self.f(y)), \(Self.f(largeur))×\(Self.f(hauteur)))"
    }

    private static func f(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

public enum Repere {
    /// Cocoa → Quartz. `hauteurEcranPrincipal` = hauteur de l'écran qui porte l'origine (`NSScreen.screens[0]`).
    public static func versQuartz(_ c: Cadre, hauteurEcranPrincipal h: Double) -> Cadre {
        Cadre(x: c.x, y: h - c.maxY, largeur: c.largeur, hauteur: c.hauteur)
    }

    /// Quartz → Cocoa (la conversion est sa propre inverse).
    public static func versCocoa(_ c: Cadre, hauteurEcranPrincipal h: Double) -> Cadre {
        versQuartz(c, hauteurEcranPrincipal: h)
    }
}
