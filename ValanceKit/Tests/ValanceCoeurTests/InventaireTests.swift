import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Inventaire : appariement fenêtres ↔ Accessibilité")
struct InventaireTests {
    func c(_ x: Double, _ w: Double = 30) -> Cadre { Cadre(x: x, y: 0, largeur: w, hauteur: 24) }

    let fenetres = [
        FenetreBarre(numero: 11, cadre: Cadre(x: 100, y: 0, largeur: 30, hauteur: 24)),
        FenetreBarre(numero: 12, cadre: Cadre(x: 140, y: 0, largeur: 30, hauteur: 24)),
        FenetreBarre(numero: 13, cadre: Cadre(x: 300, y: 0, largeur: 24, hauteur: 24)),
        FenetreBarre(numero: 99, cadre: Cadre(x: 500, y: 0, largeur: 20, hauteur: 24)),   // la nôtre
    ]

    var elements: [ElementAccessible] {
        [
            ElementAccessible(pid: 1, bundle: "com.exemple.b", nomApp: "B", titre: "B", cadre: c(141), rang: 0),
            ElementAccessible(pid: 2, bundle: "com.exemple.a", nomApp: "A", cadre: c(100), rang: 0),
            ElementAccessible(pid: 3, bundle: "com.exemple.c", nomApp: "C", identifiant: "horloge", cadre: c(-5000), rang: 2),
        ]
    }

    @Test func appariementEtSections() {
        let sep = Cadre(x: 200, y: 0, largeur: 12, hauteur: 24)
        let icones = Appariement.apparier(fenetres: fenetres, elements: elements, exclure: [99], separateur: sep, toujoursMasque: nil)
        #expect(icones.count == 4)
        #expect(icones.map(\.cle) == ["com.exemple.c#horloge", "com.exemple.a#0", "com.exemple.b#B", "fenetre#13"])
        #expect(icones[1].fenetre?.numero == 11)
        #expect(icones[2].fenetre?.numero == 12)
        #expect(icones[0].fenetre == nil)                          // hors écran, sans fenêtre
        #expect(icones.map(\.section) == [.masquee, .masquee, .masquee, .visible])
        #expect(!icones.contains { $0.fenetre?.numero == 99 })
    }

    @Test func copiesDesAutresBarres() {
        // Une barre par écran : chaque icône (et notre séparateur) y a sa copie, ramenée au même endroit.
        let f = fenetres + [
            FenetreBarre(numero: 21, cadre: Cadre(x: 101, y: 0, largeur: 30, hauteur: 24)),   // copie de A
            FenetreBarre(numero: 23, cadre: Cadre(x: 300, y: 0, largeur: 24, hauteur: 24)),   // copie de la 13
            FenetreBarre(numero: 29, cadre: Cadre(x: 500, y: 0, largeur: 20, hauteur: 24)),   // copie de la nôtre
        ]
        let icones = Appariement.apparier(fenetres: f, elements: elements, exclure: [99], separateur: nil, toujoursMasque: nil)
        #expect(icones.count == 4)
        #expect(!icones.contains { [21, 23, 29].contains($0.fenetre?.numero ?? 0) })
    }

    @Test func iconeSystemeDansUneFenetrePlusLarge() {
        // macOS 26 : Bluetooth, élément de 16 × 22 pt dans une fenêtre de 32 × 24 pt (IoU 0,46).
        let f = [FenetreBarre(numero: 1, cadre: Cadre(x: -4424, y: -200, largeur: 32, hauteur: 24)),
                 FenetreBarre(numero: 2, cadre: Cadre(x: -4424, y: -200, largeur: 32, hauteur: 24))]   // copie d'un autre écran
        let e = [ElementAccessible(pid: 1, bundle: "cc", nomApp: "Centre de contrôle", titre: "Bluetooth",
                                   cadre: Cadre(x: -4416, y: -196, largeur: 16, hauteur: 22))]
        let i = Appariement.apparier(fenetres: f, elements: e, separateur: nil, toujoursMasque: nil)
        #expect(i.count == 1)
        #expect(i.first?.fenetre?.numero == 1)
    }

    @Test func meilleurScoreDAbord() {
        // Deux éléments proches d'une même fenêtre : le plus ressemblant gagne, l'autre reste seul.
        let f = [FenetreBarre(numero: 1, cadre: c(100))]
        let e = [
            ElementAccessible(pid: 1, bundle: "x", nomApp: "X", cadre: c(108)),
            ElementAccessible(pid: 2, bundle: "y", nomApp: "Y", cadre: c(101)),
        ]
        let i = Appariement.apparier(fenetres: f, elements: e, separateur: nil, toujoursMasque: nil)
        #expect(i.first { $0.fenetre != nil }?.element?.nomApp == "Y")
        #expect(i.count == 2)
    }

    @Test func sousLeSeuilPasDAppariement() {
        let f = [FenetreBarre(numero: 1, cadre: c(100))]
        let e = [ElementAccessible(pid: 1, bundle: "x", nomApp: "X", cadre: c(120))]   // recouvrement 10/50
        let i = Appariement.apparier(fenetres: f, elements: e, separateur: nil, toujoursMasque: nil)
        #expect(i.count == 2)
        #expect(i.allSatisfy { $0.fenetre == nil || $0.element == nil })
    }

    @Test func doublonsDePlusieursEcrans() {
        let e = [
            ElementAccessible(pid: 1, bundle: "x", nomApp: "X", titre: "t", cadre: c(100)),
            ElementAccessible(pid: 1, bundle: "x", nomApp: "X", titre: "t", cadre: c(2100)),
        ]
        let i = Appariement.apparier(fenetres: [], elements: e, separateur: nil, toujoursMasque: nil)
        #expect(i.count == 1)
    }

    @Test func nomsAffiches() {
        let e = ElementAccessible(pid: 1, bundle: "x", nomApp: "Météo", titre: "18°", cadre: c(0))
        #expect(IconeBarre(fenetre: nil, element: e, section: .visible).nom == "Météo — 18°")
        let e2 = ElementAccessible(pid: 1, bundle: nil, nomApp: "Outil", titre: "Outil", cadre: c(0))
        #expect(IconeBarre(fenetre: nil, element: e2, section: .visible).nom == "Outil")
        #expect(IconeBarre(fenetre: nil, element: e2, section: .visible).cle == "Outil#Outil")
        #expect(IconeBarre(fenetre: FenetreBarre(numero: 7, cadre: c(0)), element: nil, section: .visible).nom == "Icône sans nom")
    }
}

@Suite("Règles d'affichage")
struct ReglesTests {
    func icone(_ bundle: String, _ section: Section, x: Double) -> IconeBarre {
        IconeBarre(fenetre: nil,
                   element: ElementAccessible(pid: 1, bundle: bundle, nomApp: bundle.uppercased(),
                                              cadre: Cadre(x: x, y: 0, largeur: 20, hauteur: 24)),
                   section: section)
    }

    @Test func conseilsDePlacement() {
        let icones = [icone("a", .masquee, x: 10), icone("b", .visible, x: 50), icone("c", .masquee, x: 30), icone("d", .visible, x: 70)]
        let regles: [String: RegleApp] = [
            "a": RegleApp(placement: .visible),
            "b": RegleApp(placement: .masquee),
            "c": RegleApp(placement: .toujoursMasquee),
            "d": RegleApp(placement: .libre),
        ]
        let sans = Regles.conseils(icones: icones, regles: regles, sectionToujoursMasquee: false)
        #expect(sans.map(\.icone.element?.bundle) == ["a", "b"])   // « c » : toujours masquée ≈ masquée sans 2e section
        #expect(sans[0].texte == "⌘-glissez « A » à droite de la flèche de Valance.")
        let avec = Regles.conseils(icones: icones, regles: regles, sectionToujoursMasquee: true)
        #expect(avec.map(\.voulue) == [.visible, .masquee, .toujoursMasquee])
    }

    @Test func contenuDeLaBarreSecondaire() {
        let icones = [icone("b", .masquee, x: 50), icone("a", .masquee, x: 10), icone("t", .toujoursMasquee, x: -50), icone("v", .visible, x: 90)]
        let regles: [String: RegleApp] = ["b": RegleApp(dansBarreSecondaire: false)]
        #expect(Regles.contenuBarreSecondaire(icones: icones, regles: regles, inclureToujoursMasquees: false).map(\.element?.bundle) == ["a"])
        #expect(Regles.contenuBarreSecondaire(icones: icones, regles: [:], inclureToujoursMasquees: true).map(\.element?.bundle) == ["t", "a", "b"])
    }

    @Test func iconesSurveillees() {
        let icones = [icone("a", .masquee, x: 0), icone("b", .visible, x: 10), icone("c", .masquee, x: 20)]
        let regles: [String: RegleApp] = ["a": RegleApp(signalerChangements: true), "b": RegleApp(signalerChangements: true)]
        #expect(Regles.surveillees(icones: icones, regles: regles).map(\.element?.bundle) == ["a"])
    }

    @Test func iconeSansBundleSuitLaRegleParDefaut() {
        let i = IconeBarre(fenetre: FenetreBarre(numero: 1, cadre: .zero), element: nil, section: .masquee)
        #expect(Regles.regle(pour: i, dans: ["x": RegleApp(placement: .visible)]) == RegleApp())
    }
}
