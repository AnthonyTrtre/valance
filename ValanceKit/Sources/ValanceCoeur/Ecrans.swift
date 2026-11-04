import Foundation

/// Description d'un écran, prise sur `NSScreen` par la coque d'app (repère Cocoa).
public struct EcranDecrit: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var nom: String
    /// `NSScreen.frame` (Cocoa).
    public var cadre: Cadre
    /// Hauteur de la barre des menus sur cet écran (`frame.maxY - visibleFrame.maxY`), 0 si la barre est masquée.
    public var hauteurBarre: Double
    /// Largeur de `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (nil sans encoche).
    public var largeurGaucheEncoche: Double?
    public var largeurDroiteEncoche: Double?

    public init(id: UInt32, nom: String, cadre: Cadre, hauteurBarre: Double,
                largeurGaucheEncoche: Double? = nil, largeurDroiteEncoche: Double? = nil) {
        self.id = id
        self.nom = nom
        self.cadre = cadre
        self.hauteurBarre = hauteurBarre
        self.largeurGaucheEncoche = largeurGaucheEncoche
        self.largeurDroiteEncoche = largeurDroiteEncoche
    }

    /// Hauteur de barre utilisable pour les calculs : si la barre est masquée automatiquement, on prend la
    /// hauteur standard fournie par l'appelant (`NSStatusBar.system.thickness`).
    public func hauteurBarre(parDefaut: Double) -> Double { hauteurBarre > 0 ? hauteurBarre : parDefaut }

    /// Bande de la barre des menus (Cocoa).
    public func bandeBarre(hauteurParDefaut: Double) -> Cadre {
        let h = hauteurBarre(parDefaut: hauteurParDefaut)
        return Cadre(x: cadre.minX, y: cadre.maxY - h, largeur: cadre.largeur, hauteur: h)
    }

    /// Rectangle de l'encoche (Cocoa), calculé à partir des seules largeurs des zones libres, ce qui ne dépend
    /// pas du repère dans lequel AppKit exprime `auxiliaryTop…Area`.
    public func encoche(hauteurParDefaut: Double) -> Cadre? {
        guard let g = largeurGaucheEncoche, let d = largeurDroiteEncoche else { return nil }
        let x0 = cadre.minX + g
        let x1 = cadre.maxX - d
        guard x1 - x0 >= 1 else { return nil }
        let h = hauteurBarre(parDefaut: hauteurParDefaut)
        return Cadre(x: x0, y: cadre.maxY - h, largeur: x1 - x0, hauteur: h)
    }

    public var aUneEncoche: Bool { encoche(hauteurParDefaut: 24) != nil }
}

public enum Ecrans {
    /// Écran qui contient le point (Cocoa) ; à défaut, le plus proche horizontalement.
    public static func ecran(contenant x: Double, _ y: Double, parmi ecrans: [EcranDecrit]) -> EcranDecrit? {
        if let e = ecrans.first(where: { $0.cadre.contient(x: x, y: y) }) { return e }
        // Le bord haut (y == maxY) n'est pas « dans » le cadre : on l'accepte quand même.
        if let e = ecrans.first(where: { x >= $0.cadre.minX && x < $0.cadre.maxX && abs(y - $0.cadre.maxY) < 1 }) { return e }
        return nil
    }

    /// Écran dont la barre porte ce cadre (Quartz) : celui dont le milieu de barre est le plus proche en hauteur ; à
    /// égalité (barres à la même hauteur), celui qui contient l'abscisse. Une icône masquée est hors de son écran en x,
    /// d'où la hauteur d'abord. nil si le cadre n'est près d'aucune barre.
    public static func ecranDeLaBarre(_ c: Cadre, ecrans: [EcranDecrit], hauteurEcranPrincipal h: Double,
                                      hauteurParDefaut: Double) -> EcranDecrit? {
        let ecarts = ecrans.map { e -> (EcranDecrit, Double) in
            let q = Repere.versQuartz(e.cadre, hauteurEcranPrincipal: h)
            return (e, abs(c.milieuY - (q.minY + e.hauteurBarre(parDefaut: hauteurParDefaut) / 2)))
        }
        // Au-delà de 30 pt de toute barre, ce n'est pas une icône de barre (certaines apps donnent un cadre fantaisiste).
        guard let plusPetit = ecarts.map(\.1).min(), plusPetit <= 30 else { return nil }
        let proches = ecarts.filter { $0.1 <= plusPetit + 6 }.map(\.0)
        return proches.first { $0.cadre.minX <= c.milieuX && c.milieuX < $0.cadre.maxX } ?? ecarts.first { $0.1 == plusPetit }?.0
    }

    /// Ramène un cadre de barre (Quartz) sur la barre de l'écran le plus large. Chaque écran a sa barre, calée à
    /// droite, et l'Accessibilité situe les icônes de chaque app sur l'une ou l'autre : on ne compare des positions
    /// qu'après les avoir ramenées sur la même barre.
    public static func versReference(_ c: Cadre, ecrans: [EcranDecrit], hauteurEcranPrincipal h: Double,
                                     hauteurParDefaut: Double) -> Cadre {
        guard let ref = ecrans.max(by: { $0.cadre.largeur < $1.cadre.largeur }),
              let ici = ecranDeLaBarre(c, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: hauteurParDefaut) else { return c }
        let r = Repere.versQuartz(ref.cadre, hauteurEcranPrincipal: h), i = Repere.versQuartz(ici.cadre, hauteurEcranPrincipal: h)
        return c.decale(dx: r.maxX - i.maxX, dy: r.minY - i.minY)
    }

    /// Vrai si le point (Cocoa) est dans la bande de la barre des menus d'un écran.
    public static func estDansBarre(x: Double, y: Double, ecrans: [EcranDecrit], hauteurParDefaut: Double) -> Bool {
        guard let e = ecran(contenant: x, y, parmi: ecrans) else { return false }
        let bande = e.bandeBarre(hauteurParDefaut: hauteurParDefaut)
        return x >= bande.minX && x < bande.maxX && y >= bande.minY - 0.5 && y <= bande.maxY + 0.5
    }
}

/// Longueur à donner au séparateur pour pousser hors de l'écran tout ce qui est à sa gauche.
public enum LongueurSeparateur {
    /// Plancher : même sur un tout petit écran on pousse franchement.
    public static let minimum: Double = 1_000
    /// Plafond : une fenêtre de barre démesurée coûte au WindowServer sans rien apporter.
    public static let maximum: Double = 10_000
    /// Marge ajoutée à la plus grande largeur d'écran.
    public static let marge: Double = 200
    /// Longueur quand l'icône est à l'écran (séparateur discret).
    public static let visible: Double = 12
    /// Longueur quand le séparateur doit être invisible tout en restant à sa place.
    public static let invisible: Double = 0

    /// Un `NSStatusItem` ne peut pousser une icône au-delà de la largeur de l'écran le plus large : sa position
    /// x est au plus cette largeur. Toutes les barres affichent les mêmes icônes, donc on prend le maximum.
    public static func pourMasquer(largeursEcrans: [Double]) -> Double {
        guard let plusLarge = largeursEcrans.filter({ $0.isFinite && $0 > 0 }).max() else { return 5_000 }
        return min(maximum, max(minimum, (plusLarge + marge).rounded(.up)))
    }
}
