import Foundation

/// Réglages de Valance. Le décodage tolère les clés absentes (valeurs par défaut) : une nouvelle version peut
/// ajouter un réglage sans perdre les autres.
public struct Reglages: Codable, Equatable, Sendable {
    // Général
    public var repliAutomatique = true
    public var delaiRepli: Double = 10
    public var memoriserEtat = true
    public var afficherSeparateur = true
    public var revelerAuSurvol = false
    // Sections
    public var sectionToujoursMasquee = true
    // Indicateurs
    public var afficherDisque = true
    /// Pourcentage restant de la limite hebdomadaire de Claude (lu par Claude Code, s'il est connecté).
    public var afficherClaude = false
    // Raccourcis
    public var raccourci: Raccourci? = .parDefaut
    public var raccourciToutReveler: Raccourci?
    // Fonctions avec autorisation (désactivées par défaut)
    public var inventaireActive = false
    /// Où montrer les icônes masquées quand on les révèle (remplace l'ancien interrupteur « barre secondaire »).
    public var modeAffichage: ModeAffichage = .auto
    public var signalerChangements = false
    public var dureeSignalement: Double = 8
    // Règles par app (clé : identifiant de bundle)
    public var regles: [String: RegleApp] = [:]

    public init() {}

    public static let dureeSignalementBornes: ClosedRange<Double> = 2...60

    /// Corrige les valeurs hors bornes (fichier modifié à la main, ancienne version).
    public func normalises() -> Reglages {
        var r = self
        r.delaiRepli = MachineVisibilite.borner(delaiRepli)
        if !dureeSignalement.isFinite { r.dureeSignalement = 8 }
        r.dureeSignalement = min(Self.dureeSignalementBornes.upperBound, max(Self.dureeSignalementBornes.lowerBound, r.dureeSignalement))
        if let rc = raccourci, !rc.estValide { r.raccourci = nil }
        if let rc = raccourciToutReveler, !rc.estValide || rc == r.raccourci { r.raccourciToutReveler = nil }
        return r
    }

    private enum Cles: String, CodingKey {
        case repliAutomatique, delaiRepli, memoriserEtat, afficherSeparateur, revelerAuSurvol, sectionToujoursMasquee
        case raccourci, raccourciToutReveler, inventaireActive, modeAffichage, signalerChangements, dureeSignalement
        case regles, afficherDisque, afficherClaude
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        let d = Reglages()
        repliAutomatique = try c.decodeIfPresent(Bool.self, forKey: .repliAutomatique) ?? d.repliAutomatique
        delaiRepli = try c.decodeIfPresent(Double.self, forKey: .delaiRepli) ?? d.delaiRepli
        memoriserEtat = try c.decodeIfPresent(Bool.self, forKey: .memoriserEtat) ?? d.memoriserEtat
        afficherSeparateur = try c.decodeIfPresent(Bool.self, forKey: .afficherSeparateur) ?? d.afficherSeparateur
        revelerAuSurvol = try c.decodeIfPresent(Bool.self, forKey: .revelerAuSurvol) ?? d.revelerAuSurvol
        sectionToujoursMasquee = try c.decodeIfPresent(Bool.self, forKey: .sectionToujoursMasquee) ?? d.sectionToujoursMasquee
        // Un raccourci explicitement effacé est stocké comme `null` : on le distingue d'une clé absente.
        raccourci = c.contains(.raccourci) ? try c.decodeIfPresent(Raccourci.self, forKey: .raccourci) : d.raccourci
        raccourciToutReveler = try c.decodeIfPresent(Raccourci.self, forKey: .raccourciToutReveler)
        inventaireActive = try c.decodeIfPresent(Bool.self, forKey: .inventaireActive) ?? d.inventaireActive
        modeAffichage = (try? c.decodeIfPresent(ModeAffichage.self, forKey: .modeAffichage)) ?? d.modeAffichage
        signalerChangements = try c.decodeIfPresent(Bool.self, forKey: .signalerChangements) ?? d.signalerChangements
        dureeSignalement = try c.decodeIfPresent(Double.self, forKey: .dureeSignalement) ?? d.dureeSignalement
        regles = try c.decodeIfPresent([String: RegleApp].self, forKey: .regles) ?? d.regles
        afficherDisque = try c.decodeIfPresent(Bool.self, forKey: .afficherDisque) ?? d.afficherDisque
        afficherClaude = try c.decodeIfPresent(Bool.self, forKey: .afficherClaude) ?? d.afficherClaude
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Cles.self)
        try c.encode(repliAutomatique, forKey: .repliAutomatique)
        try c.encode(delaiRepli, forKey: .delaiRepli)
        try c.encode(memoriserEtat, forKey: .memoriserEtat)
        try c.encode(afficherSeparateur, forKey: .afficherSeparateur)
        try c.encode(revelerAuSurvol, forKey: .revelerAuSurvol)
        try c.encode(sectionToujoursMasquee, forKey: .sectionToujoursMasquee)
        try c.encode(raccourci, forKey: .raccourci)   // `null` si effacé
        try c.encodeIfPresent(raccourciToutReveler, forKey: .raccourciToutReveler)
        try c.encode(inventaireActive, forKey: .inventaireActive)
        try c.encode(modeAffichage, forKey: .modeAffichage)
        try c.encode(signalerChangements, forKey: .signalerChangements)
        try c.encode(dureeSignalement, forKey: .dureeSignalement)
        try c.encode(regles, forKey: .regles)
        try c.encode(afficherDisque, forKey: .afficherDisque)
        try c.encode(afficherClaude, forKey: .afficherClaude)
    }
}

/// Stockage clé → données, pour isoler `UserDefaults` (et tester sans lui).
public protocol MagasinCleValeur: AnyObject {
    func donnees(pour cle: String) -> Data?
    func ecrire(_ donnees: Data?, pour cle: String)
}

public final class MagasinMemoire: MagasinCleValeur, @unchecked Sendable {
    private var contenu: [String: Data] = [:]
    private let verrou = NSLock()
    public init() {}
    public func donnees(pour cle: String) -> Data? {
        verrou.lock(); defer { verrou.unlock() }
        return contenu[cle]
    }
    public func ecrire(_ d: Data?, pour cle: String) {
        verrou.lock(); defer { verrou.unlock() }
        contenu[cle] = d
    }
}

/// Lecture et écriture des réglages et de l'état mémorisé.
public struct Persistance {
    public static let cleReglages = "valance.reglages.v1"
    public static let cleVisibilite = "valance.visibilite.v1"

    public let magasin: any MagasinCleValeur

    public init(magasin: any MagasinCleValeur) { self.magasin = magasin }

    /// Réglages enregistrés, ou valeurs par défaut si absents ou illisibles.
    public func chargerReglages() -> Reglages {
        guard let d = magasin.donnees(pour: Self.cleReglages),
              let r = try? JSONDecoder().decode(Reglages.self, from: d) else { return Reglages() }
        return r.normalises()
    }

    public func enregistrer(_ r: Reglages) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        magasin.ecrire(try? enc.encode(r.normalises()), pour: Self.cleReglages)
    }

    /// État de départ : l'état mémorisé si l'option est active, sinon masqué. On ne restaure jamais
    /// « tout révélé » (la section toujours masquée doit le rester après un redémarrage).
    public func visibiliteDeDepart(_ r: Reglages) -> Visibilite {
        guard r.memoriserEtat, let d = magasin.donnees(pour: Self.cleVisibilite),
              let brut = String(data: d, encoding: .utf8), let v = Visibilite(rawValue: brut) else { return .masquee }
        return v == .toutRevele ? .revelee : v
    }

    public func memoriser(_ v: Visibilite) {
        magasin.ecrire(Data(v.rawValue.utf8), pour: Self.cleVisibilite)
    }
}
