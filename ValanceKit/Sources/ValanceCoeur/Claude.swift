import Foundation

/// Limites d'utilisation de Claude, telles que Claude Code les donne (réponse à la demande `get_usage`).
public struct UtilisationClaude: Equatable, Sendable {
    /// Part utilisée de la limite hebdomadaire, de 0 à 100.
    public var semaine: Double
    public var remiseSemaine: Date?
    /// Part utilisée sur les 5 dernières heures, si cette limite s'applique.
    public var cinqHeures: Double?
    public var remiseCinqHeures: Date?

    public init(semaine: Double, remiseSemaine: Date? = nil, cinqHeures: Double? = nil, remiseCinqHeures: Date? = nil) {
        self.semaine = semaine
        self.remiseSemaine = remiseSemaine
        self.cinqHeures = cinqHeures
        self.remiseCinqHeures = remiseCinqHeures
    }

    public var restantSemaine: Double { max(0, min(100, 100 - semaine)) }

    /// Moins de 20 % restants : la barre l'affiche en orange.
    public var bientotEpuise: Bool { restantSemaine < 20 }

    /// Lit la réponse de Claude Code (`control_response`, ou seulement son objet `response`). nil si les limites
    /// ne s'appliquent pas (clé d'API) ou si le format a changé.
    public static func lire(_ donnees: Data) -> UtilisationClaude? {
        guard var o = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any] else { return nil }
        if let r = o["response"] as? [String: Any] { o = (r["response"] as? [String: Any]) ?? r }
        guard o["rate_limits_available"] as? Bool != false, let l = o["rate_limits"] as? [String: Any] else { return nil }
        func fenetre(_ cle: String) -> (Double, Date?)? {
            guard let f = l[cle] as? [String: Any], let u = (f["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return (u, (f["resets_at"] as? String).flatMap(date))
        }
        guard let s = fenetre("seven_day") else { return nil }
        let c = fenetre("five_hour")
        return UtilisationClaude(semaine: s.0, remiseSemaine: s.1, cinqHeures: c?.0, remiseCinqHeures: c?.1)
    }

    private static func date(_ texte: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: texte) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: texte)
    }
}
