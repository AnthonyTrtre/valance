import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Disposition : longueurs, ordre, sections")
struct DispositionTests {
    let L = 2760.0

    @Test func longueursSansSectionToujoursMasquee() {
        #expect(Disposition.longueurs(pour: .masquee, sectionToujoursMasquee: false, afficherSeparateur: true, longueurMasquage: L)
                == Longueurs(separateur: L, toujoursMasque: nil))
        #expect(Disposition.longueurs(pour: .revelee, sectionToujoursMasquee: false, afficherSeparateur: true, longueurMasquage: L)
                == Longueurs(separateur: LongueurSeparateur.visible, toujoursMasque: nil))
        #expect(Disposition.longueurs(pour: .toutRevele, sectionToujoursMasquee: false, afficherSeparateur: false, longueurMasquage: L)
                == Longueurs(separateur: 0, toujoursMasque: nil))
    }

    @Test func longueursAvecSectionToujoursMasquee() {
        let v = LongueurSeparateur.visible
        #expect(Disposition.longueurs(pour: .masquee, sectionToujoursMasquee: true, afficherSeparateur: true, longueurMasquage: L)
                == Longueurs(separateur: L, toujoursMasque: v))
        #expect(Disposition.longueurs(pour: .revelee, sectionToujoursMasquee: true, afficherSeparateur: true, longueurMasquage: L)
                == Longueurs(separateur: v, toujoursMasque: L))
        #expect(Disposition.longueurs(pour: .toutRevele, sectionToujoursMasquee: true, afficherSeparateur: true, longueurMasquage: L)
                == Longueurs(separateur: v, toujoursMasque: v))
    }

    @Test func unSeulSeparateurLongATousLesCoups() {
        // Jamais deux séparateurs démesurés à la fois (coût WindowServer), sauf en masqué où un seul suffit.
        for v in Visibilite.allCases {
            let l = Disposition.longueurs(pour: v, sectionToujoursMasquee: true, afficherSeparateur: true, longueurMasquage: L)
            #expect([l.separateur, l.toujoursMasque ?? 0].filter { $0 == L }.count <= 1)
        }
    }

    @Test func ordreDesIcones() {
        #expect(Disposition.ordreValide(xFleche: 1400, xSeparateur: 1380))
        #expect(!Disposition.ordreValide(xFleche: 1400, xSeparateur: 1420))   // séparateur glissé à droite
        #expect(!Disposition.ordreValide(xFleche: 1400, xSeparateur: 1400))
        #expect(Disposition.ordreValide(xFleche: nil, xSeparateur: 1420))      // inconnu : on fait confiance
        #expect(Disposition.ordreValide(xFleche: 1400, xSeparateur: 1380, xToujoursMasque: 1300))
        #expect(!Disposition.ordreValide(xFleche: 1400, xSeparateur: 1380, xToujoursMasque: 1390))
    }

    @Test func sectionsSelonLesSeparateurs() {
        let sep = Cadre(x: 1000, y: 0, largeur: 12, hauteur: 24)
        let tm = Cadre(x: 800, y: 0, largeur: 12, hauteur: 24)
        func c(_ x: Double) -> Cadre { Cadre(x: x, y: 0, largeur: 30, hauteur: 24) }
        #expect(Disposition.section(de: c(1100), separateur: sep, toujoursMasque: tm) == .visible)
        #expect(Disposition.section(de: c(900), separateur: sep, toujoursMasque: tm) == .masquee)
        #expect(Disposition.section(de: c(600), separateur: sep, toujoursMasque: tm) == .toujoursMasquee)
        #expect(Disposition.section(de: c(600), separateur: sep, toujoursMasque: nil) == .masquee)
        #expect(Disposition.section(de: c(600), separateur: nil, toujoursMasque: nil) == .visible)
        // Séparateur élargi (masqué) : il couvre l'écran, les icônes masquées sont bien plus à gauche.
        let large = Cadre(x: -1700, y: 0, largeur: 2700, hauteur: 24)
        #expect(Disposition.section(de: c(-1800), separateur: large, toujoursMasque: nil) == .masquee)
        #expect(Disposition.section(de: c(1100), separateur: large, toujoursMasque: nil) == .visible)
    }

    @Test func sectionsOrdonnees() {
        #expect(Section.visible < Section.masquee)
        #expect(Section.masquee < Section.toujoursMasquee)
    }
}
