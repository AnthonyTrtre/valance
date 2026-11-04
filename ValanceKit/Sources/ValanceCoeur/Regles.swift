import Foundation

/// Placement voulu pour les icônes d'une app.
public enum Placement: String, Codable, Sendable, CaseIterable {
    /// Pas d'avis : l'icône reste où l'utilisateur l'a mise.
    case libre
    case visible
    case masquee
    case toujoursMasquee

    public var section: Section? {
        switch self {
        case .libre: nil
        case .visible: .visible
        case .masquee: .masquee
        case .toujoursMasquee: .toujoursMasquee
        }
    }

    public var libelle: String {
        switch self {
        case .libre: "Libre"
        case .visible: "Toujours visible"
        case .masquee: "Masquée"
        case .toujoursMasquee: "Toujours masquée"
        }
    }
}

/// Règle d'affichage d'une app (clé : identifiant de bundle).
public struct RegleApp: Codable, Equatable, Sendable {
    public var placement: Placement = .libre
    /// L'icône apparaît dans la barre secondaire quand elle est masquée.
    public var dansBarreSecondaire = true
    /// Révéler brièvement la barre quand l'image de l'icône change (notification, état…).
    public var signalerChangements = false

    public init(placement: Placement = .libre, dansBarreSecondaire: Bool = true, signalerChangements: Bool = false) {
        self.placement = placement
        self.dansBarreSecondaire = dansBarreSecondaire
        self.signalerChangements = signalerChangements
    }

    private enum Cles: String, CodingKey { case placement, dansBarreSecondaire, signalerChangements }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        placement = (try? c.decodeIfPresent(Placement.self, forKey: .placement)) ?? .libre
        dansBarreSecondaire = try c.decodeIfPresent(Bool.self, forKey: .dansBarreSecondaire) ?? true
        signalerChangements = try c.decodeIfPresent(Bool.self, forKey: .signalerChangements) ?? false
    }

    public var estParDefaut: Bool { self == RegleApp() }
}

/// Conseil de placement : Valance ne déplace pas les icônes des autres apps (le ⌘-glisser simulé est trop
/// fragile sous macOS 26) ; il dit à l'utilisateur quoi déplacer, et où.
public struct Conseil: Equatable, Sendable, Identifiable {
    public var icone: IconeBarre
    public var actuelle: Section
    public var voulue: Section

    public var id: String { icone.cle }

    public var texte: String {
        let ou: String
        switch voulue {
        case .visible: ou = "à droite de la flèche de Valance"
        case .masquee: ou = Self.entreSeparateurs
        case .toujoursMasquee: ou = "à gauche du second séparateur"
        }
        return "⌘-glissez « \(icone.nom) » \(ou)."
    }

    private static let entreSeparateurs = "entre la flèche et le séparateur de Valance"
}

public enum Regles {
    public static func regle(pour icone: IconeBarre, dans regles: [String: RegleApp]) -> RegleApp {
        guard let b = icone.element?.bundle else { return RegleApp() }
        return regles[b] ?? RegleApp()
    }

    /// Icônes mal placées au regard des règles. Sans section « toujours masquée », une règle « toujours
    /// masquée » se contente de la section masquée.
    public static func conseils(icones: [IconeBarre], regles: [String: RegleApp], sectionToujoursMasquee: Bool) -> [Conseil] {
        icones.compactMap { i in
            guard var voulue = regle(pour: i, dans: regles).placement.section else { return nil }
            if voulue == .toujoursMasquee && !sectionToujoursMasquee { voulue = .masquee }
            let actuelle = i.section
            return actuelle == voulue ? nil : Conseil(icone: i, actuelle: actuelle, voulue: voulue)
        }
    }

    /// Contenu de la barre secondaire : les icônes masquées (et toujours masquées si demandé) que les règles
    /// n'excluent pas, de gauche à droite.
    public static func contenuBarreSecondaire(icones: [IconeBarre], regles: [String: RegleApp],
                                              inclureToujoursMasquees: Bool) -> [IconeBarre] {
        icones
            .filter { i in
                switch i.section {
                case .visible: false
                case .masquee: true
                case .toujoursMasquee: inclureToujoursMasquees
                }
            }
            .filter { regle(pour: $0, dans: regles).dansBarreSecondaire }
            .sorted { $0.cadre.minX < $1.cadre.minX }
    }

    /// Bundles dont les icônes doivent être surveillées (règle « signaler les changements »).
    public static func surveillees(icones: [IconeBarre], regles: [String: RegleApp]) -> [IconeBarre] {
        icones.filter { $0.section != .visible && regle(pour: $0, dans: regles).signalerChangements }
    }
}
