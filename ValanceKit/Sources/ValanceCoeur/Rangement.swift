import Foundation

/// Où montrer les icônes masquées quand on les révèle.
public enum ModeAffichage: String, Codable, Sendable, CaseIterable {
    /// Dans la barre s'il y a la place sur l'écran où l'on est, sinon dans le panneau sous la barre.
    case auto
    case barre
    case dessous

    public var libelle: String {
        switch self {
        case .auto: "Dans la barre s'il y a la place, sinon en dessous"
        case .barre: "Toujours dans la barre"
        case .dessous: "Toujours en dessous (panneau)"
        }
    }
}

/// Rangement des icônes choisi dans les réglages (V6) : Valance ⌘-glisse lui-même une icône vers sa section.
/// Ici, la seule logique pure : où lâcher, ce qui est atteignable, et si les icônes masquées tiennent dans la barre.
public enum Rangement {
    /// Point (Quartz) où lâcher une icône pour qu'elle rejoigne `section`, d'après les cadres de nos icônes, barre
    /// tout révélée. On vise juste à gauche d'un séparateur, ou juste à droite de la flèche : pendant le glisser,
    /// seules les icônes à gauche de celle qu'on tient se décalent (la barre est calée à droite), donc ce point reste
    /// du bon côté de l'ancre quel que soit le sens du déplacement.
    public static func pointDeDepot(vers section: Section, fleche: Cadre, separateur: Cadre,
                                    toujoursMasque: Cadre?) -> (x: Double, y: Double)? {
        switch section {
        case .visible: (fleche.maxX + 1, fleche.milieuY)
        case .masquee: (separateur.minX - 1, separateur.milieuY)
        case .toujoursMasquee: toujoursMasque.map { ($0.minX - 1, $0.milieuY) }
        }
    }

    /// Vrai si le point (Quartz) est dans la barre des menus d'un écran, hors de l'encoche : un clic simulé y atteint
    /// bien une icône.
    public static func estAtteignable(x: Double, y: Double, ecrans: [EcranDecrit], hauteurEcranPrincipal h: Double,
                                      hauteurParDefaut: Double) -> Bool {
        for e in ecrans {
            let q = Repere.versQuartz(e.cadre, hauteurEcranPrincipal: h)
            guard x >= q.minX + 1, x < q.maxX - 1, y >= q.minY, y < q.minY + e.hauteurBarre(parDefaut: hauteurParDefaut) else { continue }
            if let n = e.encoche(hauteurParDefaut: hauteurParDefaut), x >= n.minX, x < n.maxX { return false }
            return true
        }
        return false
    }

    /// Point de dépôt de repli quand celui visé pour masquer tombe sous une encoche (MacBook seul) : macOS accepte
    /// un dépôt sous l'encoche, on vise donc son milieu (sans dépasser le point d'origine vers la droite). Un dépôt
    /// tout contre le séparateur fait sauter l'icône voisine de l'autre côté. nil si le point n'est pas sous une encoche.
    public static func depotSousEncoche(x: Double, y: Double, ecrans: [EcranDecrit], hauteurEcranPrincipal h: Double,
                                        hauteurParDefaut: Double) -> (x: Double, y: Double)? {
        for e in ecrans {
            guard let n = e.encoche(hauteurParDefaut: hauteurParDefaut) else { continue }
            let q = Repere.versQuartz(n, hauteurEcranPrincipal: h)
            if x >= q.minX, x < q.maxX, y >= q.minY, y < q.maxY { return (min(x, q.milieuX), y) }
        }
        return nil
    }

    /// Vrai si la flèche (Quartz) est sous l'encoche, ou à sa gauche, sur l'écran dont la barre la porte : elle est
    /// alors invisible et l'utilisateur ne peut plus rien révéler d'un clic.
    public static func flecheCachee(_ f: Cadre, ecrans: [EcranDecrit], hauteurEcranPrincipal h: Double,
                                    hauteurParDefaut: Double) -> Bool {
        guard let e = Ecrans.ecranDeLaBarre(f, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: hauteurParDefaut),
              let n = e.encoche(hauteurParDefaut: hauteurParDefaut) else { return false }
        return f.minX < Repere.versQuartz(n, hauteurEcranPrincipal: h).maxX - Analyse.tolerance
    }

    /// Les icônes masquées (largeur totale `largeurIcones`) tiennent-elles à gauche de la flèche sur `ecran` ?
    /// Toutes les barres sont calées à droite et les menus de l'app à gauche : on passe donc d'un écran à l'autre
    /// par la distance de la flèche au bord droit et la largeur des menus de l'app au premier plan. Sur un écran à
    /// encoche, les icônes ne vont jamais à gauche de l'encoche ; si la flèche elle-même est sous l'encoche, rien ne
    /// tient.
    public static func tientDansLaBarre(largeurIcones: Double, distanceFlecheBordDroit: Double, largeurMenusApp: Double,
                                        ecran: EcranDecrit, marge: Double = 24) -> Bool {
        let largeur = ecran.cadre.largeur
        let xFleche = largeur - distanceFlecheBordDroit
        var gauche = max(0, largeurMenusApp)
        if ecran.largeurGaucheEncoche != nil, let d = ecran.largeurDroiteEncoche {
            let finEncoche = largeur - d
            guard xFleche >= finEncoche else { return false }
            gauche = max(gauche, finEncoche)
        }
        return xFleche - gauche - marge >= largeurIcones
    }
}
