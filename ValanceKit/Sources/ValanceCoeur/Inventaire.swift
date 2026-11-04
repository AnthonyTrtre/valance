import Foundation

/// Fenêtre d'icône de la barre (niveau 25), telle que `CGWindowListCopyWindowInfo` la donne sans autorisation :
/// un numéro et un cadre (Quartz). Sous macOS 26, le propriétaire est toujours le Centre de contrôle.
public struct FenetreBarre: Equatable, Hashable, Sendable {
    public var numero: UInt32
    public var cadre: Cadre

    public init(numero: UInt32, cadre: Cadre) {
        self.numero = numero
        self.cadre = cadre
    }
}

/// Élément de barre lu par l'Accessibilité (`AXExtrasMenuBar` d'une app) ; cadre en Quartz.
public struct ElementAccessible: Equatable, Hashable, Sendable {
    public var pid: Int32
    public var bundle: String?
    public var nomApp: String
    public var titre: String?
    public var identifiant: String?
    public var cadre: Cadre
    /// Rang de l'élément dans la liste de son app (pour l'actionner plus tard).
    public var rang: Int

    public init(pid: Int32, bundle: String?, nomApp: String, titre: String? = nil, identifiant: String? = nil,
                cadre: Cadre, rang: Int = 0) {
        self.pid = pid
        self.bundle = bundle
        self.nomApp = nomApp
        self.titre = titre
        self.identifiant = identifiant
        self.cadre = cadre
        self.rang = rang
    }
}

/// Icône de la barre, après appariement.
public struct IconeBarre: Equatable, Hashable, Sendable, Identifiable {
    public var fenetre: FenetreBarre?
    public var element: ElementAccessible?
    public var section: Section

    public init(fenetre: FenetreBarre?, element: ElementAccessible?, section: Section) {
        self.fenetre = fenetre
        self.element = element
        self.section = section
    }

    public var cadre: Cadre { element?.cadre ?? fenetre?.cadre ?? .zero }

    /// Clé stable d'une icône d'une session à l'autre (le numéro de fenêtre, lui, change).
    public var cle: String {
        if let e = element {
            let app = e.bundle ?? e.nomApp
            if let i = e.identifiant, !i.isEmpty { return "\(app)#\(i)" }
            if let t = e.titre, !t.isEmpty { return "\(app)#\(t)" }
            return "\(app)#\(e.rang)"
        }
        if let f = fenetre { return "fenetre#\(f.numero)" }
        return "inconnue"
    }

    public var id: String { cle }

    /// Nom à afficher : titre AX, sinon nom de l'app, sinon « Icône ».
    public var nom: String {
        if let e = element {
            if let t = e.titre, !t.isEmpty, t != e.nomApp { return "\(e.nomApp) — \(t)" }
            return e.nomApp
        }
        return "Icône sans nom"
    }
}

public enum Appariement {
    /// Seuil de ressemblance des cadres (intersection sur union) pour apparier une fenêtre et un élément.
    public static let seuil = 0.5

    /// Associe chaque fenêtre de barre à l'élément d'Accessibilité dont le cadre lui ressemble le plus
    /// (glouton par ressemblance décroissante, chaque élément servant une seule fois). Les fenêtres qui
    /// correspondent à nos propres icônes sont exclues. Le résultat est trié de gauche à droite.
    public static func apparier(fenetres: [FenetreBarre], elements: [ElementAccessible],
                                exclure: Set<UInt32> = [], separateur: Cadre?, toujoursMasque: Cadre?) -> [IconeBarre] {
        let fen = fenetres.filter { !exclure.contains($0.numero) && !$0.cadre.estVide }
        var couples: [(f: Int, e: Int, score: Double)] = []
        for (i, f) in fen.enumerated() {
            for (j, e) in elements.enumerated() {
                let s = f.cadre.iou(e.cadre)
                if s >= seuil { couples.append((i, j, s)) }
            }
        }
        couples.sort { $0.score != $1.score ? $0.score > $1.score : ($0.f, $0.e) < ($1.f, $1.e) }
        var fPris = Set<Int>(), ePris = Set<Int>()
        var icones: [IconeBarre] = []
        for c in couples where !fPris.contains(c.f) && !ePris.contains(c.e) {
            fPris.insert(c.f)
            ePris.insert(c.e)
            icones.append(IconeBarre(fenetre: fen[c.f], element: elements[c.e], section: .visible))
        }
        for (i, f) in fen.enumerated() where !fPris.contains(i) {
            icones.append(IconeBarre(fenetre: f, element: nil, section: .visible))
        }
        // Éléments AX sans fenêtre : souvent des icônes hors de l'écran (masquées) que le WindowServer ne liste
        // plus ; on les garde, leur cadre AX suffit pour la section.
        for (j, e) in elements.enumerated() where !ePris.contains(j) && !e.cadre.estVide {
            icones.append(IconeBarre(fenetre: nil, element: e, section: .visible))
        }
        for k in icones.indices {
            icones[k].section = Disposition.section(de: icones[k].cadre, separateur: separateur, toujoursMasque: toujoursMasque)
        }
        // Doublons (même icône vue sur plusieurs écrans) : on garde la première occurrence de chaque clé AX.
        var vues = Set<String>()
        icones = icones.filter { i in
            guard i.element != nil else { return true }
            return vues.insert(i.cle).inserted
        }
        return icones.sorted { $0.cadre.minX != $1.cadre.minX ? $0.cadre.minX < $1.cadre.minX : $0.cle < $1.cle }
    }
}
