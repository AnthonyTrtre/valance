import Foundation

/// Diagnostic de l'encoche pour un écran : quelles icônes tombent dessous (macOS ne les replie pas, elles
/// passent simplement derrière la caméra) et combien de place il reste à droite.
public struct DiagnosticEncoche: Equatable, Sendable {
    public var ecran: UInt32
    /// Encoche en Quartz.
    public var encoche: Cadre
    /// Indices (dans la liste fournie) des fenêtres d'icônes qui chevauchent l'encoche.
    public var sousEncoche: [Int]
    /// Largeur libre entre l'encoche et le bord droit, en points.
    public var largeurDroite: Double

    public var aDesIconesCachees: Bool { !sousEncoche.isEmpty }
}

public enum Analyse {
    /// Tolérance de chevauchement : un ou deux points de recouvrement sont dus aux arrondis.
    public static let tolerance: Double = 2

    /// `fenetres` : cadres des icônes en Quartz ; `hauteurEcranPrincipal` sert à convertir l'écran.
    public static func encoche(ecran: EcranDecrit, fenetres: [Cadre], hauteurEcranPrincipal: Double,
                               hauteurParDefaut: Double) -> DiagnosticEncoche? {
        guard let enc = ecran.encoche(hauteurParDefaut: hauteurParDefaut) else { return nil }
        let encQ = Repere.versQuartz(enc, hauteurEcranPrincipal: hauteurEcranPrincipal)
        let ecranQ = Repere.versQuartz(ecran.cadre, hauteurEcranPrincipal: hauteurEcranPrincipal)
        let bande = Cadre(x: ecranQ.minX, y: ecranQ.minY, largeur: ecranQ.largeur, hauteur: encQ.hauteur)
        var sous: [Int] = []
        for (i, f) in fenetres.enumerated() {
            // L'icône doit être dans la bande de barre de CET écran (même ligne), puis chevaucher l'encoche.
            guard f.milieuY >= bande.minY - 1, f.milieuY <= bande.maxY + 1 else { continue }
            if f.recouvrementHorizontal(encQ) > tolerance { sous.append(i) }
        }
        return DiagnosticEncoche(ecran: ecran.id, encoche: encQ, sousEncoche: sous,
                                 largeurDroite: ecran.largeurDroiteEncoche ?? 0)
    }
}

/// Mise en page de la barre secondaire : un panneau sous la barre, aligné à droite sous la flèche, qui ne
/// déborde jamais de l'écran et passe à la ligne si les icônes ne tiennent pas.
public struct MiseEnPagePanneau: Equatable, Sendable {
    /// Cadre du panneau (Cocoa).
    public var cadre: Cadre
    /// Cadres des vignettes, relatifs au panneau (origine en bas à gauche du panneau).
    public var vignettes: [Cadre]

    public static let marge: Double = 6
    public static let espacement: Double = 4
    public static let ecartSousBarre: Double = 4

    /// - Parameters:
    ///   - tailles: taille de chaque vignette (largeur, hauteur) en points, dans l'ordre d'affichage.
    ///   - ancreX: abscisse (Cocoa) du bord droit souhaité, en général le bord droit de la flèche.
    ///   - ecran: écran où afficher le panneau ; `hauteurBarre` doit être > 0 ou fournie par défaut.
    public static func calculer(tailles: [(largeur: Double, hauteur: Double)], ancreX: Double, ecran: EcranDecrit,
                                hauteurParDefaut: Double) -> MiseEnPagePanneau {
        let barre = ecran.bandeBarre(hauteurParDefaut: hauteurParDefaut)
        let largeurMax = max(60, ecran.cadre.largeur - 2 * marge)
        let hauteurLigne = max(tailles.map(\.hauteur).max() ?? 22, 16)

        // Remplissage des lignes de gauche à droite.
        var lignes: [[Int]] = [[]]
        var largeurLigne = 0.0
        for (i, t) in tailles.enumerated() {
            let w = max(1, t.largeur)
            let besoin = (lignes[lignes.count - 1].isEmpty ? 0 : espacement) + w
            if !lignes[lignes.count - 1].isEmpty && largeurLigne + besoin + 2 * marge > largeurMax {
                lignes.append([i])
                largeurLigne = w
            } else {
                lignes[lignes.count - 1].append(i)
                largeurLigne += besoin
            }
        }
        let largeurs = lignes.map { l in
            l.reduce(0.0) { $0 + max(1, tailles[$1].largeur) } + Double(max(0, l.count - 1)) * espacement
        }
        let largeurPanneau = min(largeurMax, max(40, (largeurs.max() ?? 0) + 2 * marge))
        let nLignes = Double(lignes.count)
        let hauteurPanneau = nLignes * hauteurLigne + max(0, nLignes - 1) * espacement + 2 * marge

        // Aligné à droite sur l'ancre, puis ramené dans l'écran.
        var x = ancreX - largeurPanneau
        x = min(x, ecran.cadre.maxX - marge - largeurPanneau)
        x = max(x, ecran.cadre.minX + marge)
        let y = barre.minY - ecartSousBarre - hauteurPanneau

        var vignettes = [Cadre](repeating: .zero, count: tailles.count)
        for (n, ligne) in lignes.enumerated() {
            // Première ligne en haut du panneau.
            let yLigne = hauteurPanneau - marge - Double(n + 1) * hauteurLigne - Double(n) * espacement
            var xc = marge
            for i in ligne {
                let w = max(1, tailles[i].largeur), h = tailles[i].hauteur
                vignettes[i] = Cadre(x: xc, y: yLigne + (hauteurLigne - h) / 2, largeur: w, hauteur: h)
                xc += w + espacement
            }
        }
        return MiseEnPagePanneau(cadre: Cadre(x: x, y: y, largeur: largeurPanneau, hauteur: hauteurPanneau),
                                 vignettes: vignettes)
    }
}
