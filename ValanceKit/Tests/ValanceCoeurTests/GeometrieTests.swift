import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Géométrie et repères")
struct GeometrieTests {
    @Test func intersectionEtIoU() {
        let a = Cadre(x: 0, y: 0, largeur: 10, hauteur: 10)
        let b = Cadre(x: 5, y: 0, largeur: 10, hauteur: 10)
        #expect(a.intersection(b) == Cadre(x: 5, y: 0, largeur: 5, hauteur: 10))
        #expect(abs(a.iou(b) - 50.0 / 150.0) < 1e-9)
        #expect(a.iou(a) == 1)
        #expect(a.intersection(Cadre(x: 10, y: 0, largeur: 5, hauteur: 5)) == nil)   // bords qui se touchent
        #expect(a.recouvrementHorizontal(Cadre(x: 8, y: 500, largeur: 10, hauteur: 1)) == 2)
    }

    @Test func contientExclutLeBordDroit() {
        let a = Cadre(x: 0, y: 0, largeur: 10, hauteur: 10)
        #expect(a.contient(x: 0, y: 0))
        #expect(!a.contient(x: 10, y: 5))
    }

    @Test func conversionCocoaQuartz() {
        // Écran principal de 982 pt de haut ; une icône de barre de 37 pt en haut de l'écran.
        let cocoa = Cadre(x: 100, y: 945, largeur: 30, hauteur: 37)
        let quartz = Repere.versQuartz(cocoa, hauteurEcranPrincipal: 982)
        #expect(quartz == Cadre(x: 100, y: 0, largeur: 30, hauteur: 37))
        #expect(Repere.versCocoa(quartz, hauteurEcranPrincipal: 982) == cocoa)
        // Écran secondaire placé au-dessus du principal : y Quartz négatif.
        let haut = Cadre(x: 0, y: 982, largeur: 1920, hauteur: 1080)
        #expect(Repere.versQuartz(haut, hauteurEcranPrincipal: 982).y == -1080)
    }

    @Test func descriptionLisible() {
        #expect(Cadre(x: 1, y: 2.5, largeur: 3, hauteur: 4).description == "(1, 2.5, 3×4)")
    }
}

@Suite("Écrans, encoche et longueur du séparateur")
struct EcransTests {
    static let macBook = EcranDecrit(id: 1, nom: "Écran intégré", cadre: Cadre(x: 0, y: 0, largeur: 1512, hauteur: 982),
                                     hauteurBarre: 37, largeurGaucheEncoche: 662, largeurDroiteEncoche: 662)
    static let externe = EcranDecrit(id: 2, nom: "Externe", cadre: Cadre(x: 1512, y: 0, largeur: 2560, hauteur: 1440),
                                     hauteurBarre: 25)

    @Test func encocheCalculeeParLesLargeurs() {
        let e = Self.macBook.encoche(hauteurParDefaut: 24)
        #expect(e == Cadre(x: 662, y: 945, largeur: 188, hauteur: 37))
        #expect(Self.macBook.aUneEncoche)
        #expect(!Self.externe.aUneEncoche)
        #expect(Self.externe.encoche(hauteurParDefaut: 24) == nil)
    }

    @Test func encocheAbsenteSiZonesJointives() {
        let e = EcranDecrit(id: 3, nom: "x", cadre: Cadre(x: 0, y: 0, largeur: 1000, hauteur: 800), hauteurBarre: 24,
                            largeurGaucheEncoche: 500, largeurDroiteEncoche: 500)
        #expect(e.encoche(hauteurParDefaut: 24) == nil)
    }

    @Test func barreMasqueeUtiliseLaHauteurParDefaut() {
        var e = Self.externe
        e.hauteurBarre = 0
        #expect(e.bandeBarre(hauteurParDefaut: 24) == Cadre(x: 1512, y: 1416, largeur: 2560, hauteur: 24))
    }

    @Test func sourisDansLaBarreSurChaqueEcran() {
        let ecrans = [Self.macBook, Self.externe]
        #expect(Ecrans.estDansBarre(x: 100, y: 960, ecrans: ecrans, hauteurParDefaut: 24))
        #expect(Ecrans.estDansBarre(x: 100, y: 982, ecrans: ecrans, hauteurParDefaut: 24))   // bord haut
        #expect(!Ecrans.estDansBarre(x: 100, y: 900, ecrans: ecrans, hauteurParDefaut: 24))
        #expect(Ecrans.estDansBarre(x: 2000, y: 1430, ecrans: ecrans, hauteurParDefaut: 24))
        #expect(!Ecrans.estDansBarre(x: 2000, y: 1400, ecrans: ecrans, hauteurParDefaut: 24))
        #expect(!Ecrans.estDansBarre(x: -50, y: 960, ecrans: ecrans, hauteurParDefaut: 24))  // hors de tout écran
        #expect(Ecrans.ecran(contenant: 2000, 10, parmi: ecrans)?.id == 2)
    }

    @Test func longueurDeMasquage() {
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: [1512, 2560]) == 2760)
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: [1512]) == 1712)
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: []) == 5000)
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: [300]) == LongueurSeparateur.minimum)
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: [20_000]) == LongueurSeparateur.maximum)
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: [.nan, -3, 1512]) == 1712)
        #expect(LongueurSeparateur.pourMasquer(largeursEcrans: [1511.5]) == 1712)   // arrondi vers le haut
    }

    @Test func laLongueurSuffitSurLeGrandEcran() {
        // Le séparateur peut être n'importe où : sa distance au bord gauche ne dépasse jamais la largeur de l'écran.
        let longueur = LongueurSeparateur.pourMasquer(largeursEcrans: [Self.macBook.cadre.largeur, Self.externe.cadre.largeur])
        #expect(longueur > Self.externe.cadre.largeur)
    }
}
