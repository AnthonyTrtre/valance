import Foundation

/// Ce qui est montré dans la barre.
/// - `masquee` : la section « masquée » (à gauche du séparateur) est poussée hors de l'écran ;
/// - `revelee` : la section masquée est à l'écran, la section « toujours masquée » reste cachée ;
/// - `toutRevele` : tout est à l'écran (⌥-clic sur la flèche).
public enum Visibilite: String, Codable, Sendable, CaseIterable {
    case masquee
    case revelee
    case toutRevele

    public var estRevelee: Bool { self != .masquee }
}

/// Les trois sections, de droite à gauche : visible | séparateur | masquée | séparateur 2 | toujours masquée.
public enum Section: String, Codable, Sendable, CaseIterable, Comparable {
    case visible
    case masquee
    case toujoursMasquee

    public static func < (a: Section, b: Section) -> Bool { a.rang < b.rang }
    private var rang: Int {
        switch self {
        case .visible: 0
        case .masquee: 1
        case .toujoursMasquee: 2
        }
    }

    public var libelle: String {
        switch self {
        case .visible: "Visible"
        case .masquee: "Masquée"
        case .toujoursMasquee: "Toujours masquée"
        }
    }
}

/// Longueurs des deux séparateurs (en points) pour une visibilité donnée.
public struct Longueurs: Equatable, Sendable {
    public var separateur: Double
    /// nil si la section « toujours masquée » est désactivée (le second séparateur n'existe pas).
    public var toujoursMasque: Double?

    public init(separateur: Double, toujoursMasque: Double?) {
        self.separateur = separateur
        self.toujoursMasque = toujoursMasque
    }
}

public enum Disposition {
    /// Longueurs à appliquer. `longueurMasquage` vient de `LongueurSeparateur.pourMasquer`.
    public static func longueurs(pour visibilite: Visibilite, sectionToujoursMasquee: Bool,
                                 afficherSeparateur: Bool, longueurMasquage: Double) -> Longueurs {
        let court = afficherSeparateur ? LongueurSeparateur.visible : LongueurSeparateur.invisible
        guard sectionToujoursMasquee else {
            return Longueurs(separateur: visibilite == .masquee ? longueurMasquage : court, toujoursMasque: nil)
        }
        switch visibilite {
        case .masquee:
            // Le second séparateur est déjà hors de l'écran (à gauche du premier) : inutile de l'élargir.
            return Longueurs(separateur: longueurMasquage, toujoursMasque: LongueurSeparateur.repere)
        case .revelee:
            return Longueurs(separateur: court, toujoursMasque: longueurMasquage)
        case .toutRevele:
            return Longueurs(separateur: court, toujoursMasque: LongueurSeparateur.repere)
        }
    }

    /// Ordre attendu de nos icônes, de gauche à droite : [toujours masqué] < séparateur < flèche.
    /// Si l'utilisateur a ⌘-glissé le séparateur à droite de la flèche, l'élargir pousserait la flèche hors de
    /// l'écran et il n'y aurait plus moyen de tout révéler : on refuse alors de masquer.
    /// Abscisses dans un même repère (n'importe lequel, seul l'ordre horizontal compte).
    public static func ordreValide(xFleche: Double?, xSeparateur: Double?, xToujoursMasque: Double? = nil) -> Bool {
        guard let f = xFleche, let s = xSeparateur else { return true }   // positions inconnues : on fait confiance
        guard s < f else { return false }
        if let t = xToujoursMasque, t >= s { return false }
        return true
    }

    /// Section d'une icône selon son abscisse et celle de nos séparateurs (même repère).
    /// Une icône est à gauche d'un séparateur si son milieu est à gauche du bord gauche de celui-ci.
    public static func section(de cadre: Cadre, separateur: Cadre?, toujoursMasque: Cadre?) -> Section {
        guard let s = separateur else { return .visible }
        if cadre.milieuX >= s.minX { return .visible }
        if let t = toujoursMasque, cadre.milieuX < t.minX { return .toujoursMasquee }
        return .masquee
    }
}
