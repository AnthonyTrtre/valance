import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Rangement : dépôt, atteignabilité, place dans la barre")
struct RangementTests {
    let fleche = Cadre(x: -1224, y: -197, largeur: 24, hauteur: 24)
    let separateur = Cadre(x: -1240, y: -197, largeur: 12, hauteur: 24)
    let second = Cadre(x: -1400, y: -197, largeur: 12, hauteur: 24)

    @Test func pointsDeDepot() {
        let v = Rangement.pointDeDepot(vers: .visible, fleche: fleche, separateur: separateur, toujoursMasque: second)
        #expect(v?.x == -1199)
        #expect(v?.y == -185)
        #expect(Rangement.pointDeDepot(vers: .masquee, fleche: fleche, separateur: separateur, toujoursMasque: nil)?.x == -1241)
        #expect(Rangement.pointDeDepot(vers: .toujoursMasquee, fleche: fleche, separateur: separateur, toujoursMasque: second)?.x == -1401)
        #expect(Rangement.pointDeDepot(vers: .toujoursMasquee, fleche: fleche, separateur: separateur, toujoursMasque: nil) == nil)
    }

    // MacBook 14" (encoche) à l'origine, grand écran à gauche, un peu plus haut.
    let macbook = EcranDecrit(id: 1, nom: "MacBook", cadre: Cadre(x: 0, y: 0, largeur: 1728, hauteur: 1117), hauteurBarre: 38,
                              largeurGaucheEncoche: 764, largeurDroiteEncoche: 779)
    let large = EcranDecrit(id: 2, nom: "Large", cadre: Cadre(x: -3440, y: -123, largeur: 3440, hauteur: 1440), hauteurBarre: 24)

    @Test func atteignable() {
        let ecrans = [macbook, large]
        #expect(Rangement.estAtteignable(x: -1200, y: -190, ecrans: ecrans, hauteurEcranPrincipal: 1117, hauteurParDefaut: 24))
        #expect(Rangement.estAtteignable(x: 1500, y: 10, ecrans: ecrans, hauteurEcranPrincipal: 1117, hauteurParDefaut: 24))
        #expect(!Rangement.estAtteignable(x: 860, y: 10, ecrans: ecrans, hauteurEcranPrincipal: 1117, hauteurParDefaut: 24))   // encoche
        #expect(!Rangement.estAtteignable(x: -4000, y: -190, ecrans: ecrans, hauteurEcranPrincipal: 1117, hauteurParDefaut: 24)) // hors écran
        #expect(!Rangement.estAtteignable(x: 1500, y: 300, ecrans: ecrans, hauteurEcranPrincipal: 1117, hauteurParDefaut: 24))  // sous la barre
    }

    @Test func placeSurLeGrandEcran() {
        // Flèche à 1224 pt du bord droit, menus de l'app sur 500 pt : 3440 - 1224 - 500 - 24 = 1692 pt de libre.
        #expect(Rangement.tientDansLaBarre(largeurIcones: 600, distanceFlecheBordDroit: 1224, largeurMenusApp: 500, ecran: large))
        #expect(!Rangement.tientDansLaBarre(largeurIcones: 1800, distanceFlecheBordDroit: 1224, largeurMenusApp: 500, ecran: large))
    }

    @Test func encocheDuMacBook() {
        // Fin de l'encoche à 1728 - 779 = 949 pt. Flèche à 400 pt du bord droit : x = 1328, 1328 - 949 - 24 = 355 pt.
        #expect(Rangement.tientDansLaBarre(largeurIcones: 300, distanceFlecheBordDroit: 400, largeurMenusApp: 200, ecran: macbook))
        #expect(!Rangement.tientDansLaBarre(largeurIcones: 400, distanceFlecheBordDroit: 400, largeurMenusApp: 200, ecran: macbook))
        // Des menus d'app plus longs que l'encoche réduisent encore la place.
        #expect(!Rangement.tientDansLaBarre(largeurIcones: 300, distanceFlecheBordDroit: 400, largeurMenusApp: 1100, ecran: macbook))
        // Flèche sous l'encoche : rien ne tient.
        #expect(!Rangement.tientDansLaBarre(largeurIcones: 0, distanceFlecheBordDroit: 1224, largeurMenusApp: 0, ecran: macbook))
    }
}

@Suite("Barres de plusieurs écrans ramenées sur la plus large")
struct ReferenceTests {
    // Disposition réelle : MacBook (encoche) principal, écran ultra-large à gauche, écran 1080p encore à gauche.
    let ecrans = [
        EcranDecrit(id: 1, nom: "MacBook", cadre: Cadre(x: 0, y: 0, largeur: 1728, hauteur: 1117), hauteurBarre: 38,
                    largeurGaucheEncoche: 764, largeurDroiteEncoche: 779),
        EcranDecrit(id: 2, nom: "Large", cadre: Cadre(x: -3440, y: -123, largeur: 3440, hauteur: 1440), hauteurBarre: 24),
        EcranDecrit(id: 3, nom: "HD", cadre: Cadre(x: -5360, y: 40, largeur: 1920, hauteur: 1080), hauteurBarre: 24),
    ]

    func ref(_ c: Cadre) -> Cadre { Ecrans.versReference(c, ecrans: ecrans, hauteurEcranPrincipal: 1117, hauteurParDefaut: 24) }

    @Test func memeIconeSurDeuxBarres() {
        // La flèche de Valance vue sur le MacBook (à 1124 pt du bord droit) et sur le grand écran : même place.
        // (Seule l'abscisse compte : la barre du MacBook est plus haute, l'icône y est centrée autrement.)
        #expect(ref(Cadre(x: 604, y: 4, largeur: 24, hauteur: 24)).x == -1124)
        #expect(ref(Cadre(x: -1124, y: -197, largeur: 24, hauteur: 24)) == Cadre(x: -1124, y: -197, largeur: 24, hauteur: 24))
    }

    @Test func iconeMasqueeHorsDeSonEcran() {
        // Masquée sur le grand écran, son x tombe dans la plage de l'écran HD : c'est la hauteur qui tranche.
        #expect(ref(Cadre(x: -4880, y: -197, largeur: 34, hauteur: 24)).x == -4880)
        // Masquée sur le MacBook : ramenée de 0 à -… sur le grand écran.
        #expect(ref(Cadre(x: -3000, y: 4, largeur: 34, hauteur: 24)).x == -3000 - 1728)
    }

    @Test func barreDeLEcranHD() {
        // Écran HD : Quartz y = 1117 - 1120 = -3 ; bord droit -3440. Une icône à 100 pt du bord droit.
        #expect(ref(Cadre(x: -3540, y: -3, largeur: 24, hauteur: 24)) == Cadre(x: -100, y: -200, largeur: 24, hauteur: 24))
    }

    @Test func cadreLoinDeToutesLesBarres() {
        // CleanMyMac annonce son icône en bas de l'écran du MacBook : ignorée.
        #expect(Ecrans.ecranDeLaBarre(Cadre(x: 7, y: 1116, largeur: 24, hauteur: 1), ecrans: ecrans,
                                      hauteurEcranPrincipal: 1117, hauteurParDefaut: 24) == nil)
    }
}
