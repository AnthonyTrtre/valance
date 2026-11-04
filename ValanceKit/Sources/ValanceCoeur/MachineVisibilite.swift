import Foundation

/// Machine à états masqué / révélé / repli automatique. Pure : le temps est passé en paramètre, et elle ne fait
/// rien elle-même ; elle renvoie des effets que la coque d'app exécute (longueurs, minuterie).
public struct MachineVisibilite: Sendable {
    public enum Evenement: Equatable, Sendable {
        /// Clic sur la flèche ou raccourci : masque si révélé, révèle si masqué.
        case basculer
        /// ⌥-clic ou second raccourci : tout révéler (ou tout masquer si déjà tout révélé).
        case basculerTout
        case reveler
        case masquer
        /// Révélation brève demandée par une règle (icône qui change) ou la barre secondaire.
        case revelerTemporairement(duree: TimeInterval)
        /// La minuterie de repli est arrivée. La coque dit si la souris est dans la barre ou si un menu est
        /// ouvert : on ne replie jamais sous les doigts de l'utilisateur.
        case echeance(sourisDansBarre: Bool, menuOuvert: Bool)
        /// L'utilisateur interagit avec la barre (survol, clic) : on repousse le repli.
        case activite
        /// Les réglages de repli ont changé.
        case configurer(repliAutomatique: Bool, delai: TimeInterval)
    }

    public enum Effet: Equatable, Sendable {
        case appliquer(Visibilite)
        case planifierRepli(Date)
        case annulerRepli
    }

    /// Délai minimal et maximal du repli (secondes).
    public static let delaiMinimal: TimeInterval = 2
    public static let delaiMaximal: TimeInterval = 600
    /// Relance quand le repli tombe pendant que l'utilisateur est dans la barre ou dans un menu.
    public static let relance: TimeInterval = 2

    public private(set) var visibilite: Visibilite
    public private(set) var echeanceRepli: Date?
    public private(set) var repliAutomatique: Bool
    public private(set) var delai: TimeInterval
    /// Un repli « temporaire » (révélation brève) s'applique même si le repli automatique est coupé.
    public private(set) var repliTemporaire = false

    public init(visibilite: Visibilite = .masquee, repliAutomatique: Bool = true, delai: TimeInterval = 10) {
        self.visibilite = visibilite
        self.repliAutomatique = repliAutomatique
        self.delai = Self.borner(delai)
    }

    public static func borner(_ d: TimeInterval) -> TimeInterval {
        guard d.isFinite else { return 10 }
        return min(delaiMaximal, max(delaiMinimal, d))
    }

    /// Effets à appliquer au lancement (état restauré ou masqué).
    public mutating func demarrer(maintenant: Date) -> [Effet] {
        var effets: [Effet] = [.appliquer(visibilite)]
        if visibilite.estRevelee && repliAutomatique {
            effets += planifier(maintenant.addingTimeInterval(delai))
        }
        return effets
    }

    public mutating func traiter(_ e: Evenement, maintenant: Date) -> [Effet] {
        switch e {
        case .basculer:
            return visibilite.estRevelee ? passer(a: .masquee, maintenant) : passer(a: .revelee, maintenant)
        case .basculerTout:
            return visibilite == .toutRevele ? passer(a: .masquee, maintenant) : passer(a: .toutRevele, maintenant)
        case .reveler:
            return visibilite.estRevelee ? relancerSiBesoin(maintenant) : passer(a: .revelee, maintenant)
        case .masquer:
            return passer(a: .masquee, maintenant)
        case .revelerTemporairement(let duree):
            let d = max(1, duree.isFinite ? duree : 5)
            if visibilite.estRevelee {
                // Déjà révélé par l'utilisateur : on ne raccourcit pas son repli, on le prolonge au besoin.
                let cible = maintenant.addingTimeInterval(d)
                if let ech = echeanceRepli, ech >= cible { return [] }
                if echeanceRepli == nil && !repliTemporaire && !repliAutomatique { return [] }
                return planifier(cible)
            }
            visibilite = .revelee
            repliTemporaire = true
            return [.appliquer(.revelee)] + planifier(maintenant.addingTimeInterval(d))
        case .echeance(let souris, let menu):
            guard visibilite.estRevelee, let ech = echeanceRepli else { return [] }
            // Minuterie obsolète (déclenchée avant l'échéance courante, par exemple après une relance).
            guard maintenant >= ech.addingTimeInterval(-0.05) else { return [] }
            if souris || menu {
                return planifier(maintenant.addingTimeInterval(Self.relance))
            }
            return passer(a: .masquee, maintenant)
        case .activite:
            return relancerSiBesoin(maintenant)
        case .configurer(let auto, let d):
            repliAutomatique = auto
            delai = Self.borner(d)
            guard visibilite.estRevelee, !repliTemporaire else { return [] }
            if auto { return planifier(maintenant.addingTimeInterval(delai)) }
            return annuler()
        }
    }

    // MARK: - Interne

    private mutating func passer(a cible: Visibilite, _ maintenant: Date) -> [Effet] {
        let change = cible != visibilite
        visibilite = cible
        repliTemporaire = false
        var effets: [Effet] = change ? [.appliquer(cible)] : []
        if cible.estRevelee && repliAutomatique {
            effets += planifier(maintenant.addingTimeInterval(delai))
        } else {
            effets += annuler()
        }
        return effets
    }

    private mutating func relancerSiBesoin(_ maintenant: Date) -> [Effet] {
        guard visibilite.estRevelee, echeanceRepli != nil else { return [] }
        let d = repliTemporaire ? Self.relance : delai
        let cible = maintenant.addingTimeInterval(d)
        if let ech = echeanceRepli, ech >= cible { return [] }
        return planifier(cible)
    }

    private mutating func planifier(_ date: Date) -> [Effet] {
        echeanceRepli = date
        return [.planifierRepli(date)]
    }

    private mutating func annuler() -> [Effet] {
        guard echeanceRepli != nil else { return [] }
        echeanceRepli = nil
        return [.annulerRepli]
    }
}
