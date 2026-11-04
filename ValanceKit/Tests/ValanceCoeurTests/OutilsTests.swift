import Dispatch
import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Empreintes d'images et détection de changements")
struct EmpreinteTests {
    func degrade(_ w: Int, _ h: Int, inverse: Bool = false) -> ImageGrise {
        var p: [UInt8] = []
        for _ in 0..<h {
            for x in 0..<w {
                let v = UInt8(x * 255 / max(1, w - 1))
                p.append(inverse ? 255 - v : v)
            }
        }
        return ImageGrise(largeur: w, hauteur: h, pixels: p)
    }

    func bruit(_ w: Int, _ h: Int, graine: UInt64) -> ImageGrise {
        var g = GenerateurDeterministe(graine: graine)
        return ImageGrise(largeur: w, hauteur: h, pixels: (0..<(w * h)).map { _ in UInt8(g.entier(0...255)) })
    }

    func agrandir(_ img: ImageGrise, _ k: Int) -> ImageGrise {
        var p: [UInt8] = []
        for y in 0..<(img.hauteur * k) {
            for x in 0..<(img.largeur * k) { p.append(img.pixel(x / k, y / k)) }
        }
        return ImageGrise(largeur: img.largeur * k, hauteur: img.hauteur * k, pixels: p)
    }

    @Test func degradesOpposes() throws {
        let a = try #require(Empreinte(degrade(18, 16)))
        let b = try #require(Empreinte(degrade(18, 16, inverse: true)))
        #expect(a.bits == 0)
        #expect(b.bits == .max)
        #expect(a.distance(b) == 64)
        #expect(a.description == "0000000000000000")
    }

    @Test func insensibleALEchelle() throws {
        let img = bruit(18, 16, graine: 7)
        let a = try #require(Empreinte(img))
        let b = try #require(Empreinte(agrandir(img, 2)))
        #expect(a.distance(b) == 0)
    }

    @Test func imagesDifferentesEloignees() throws {
        let a = try #require(Empreinte(bruit(18, 16, graine: 1)))
        let b = try #require(Empreinte(bruit(18, 16, graine: 2)))
        #expect(a.distance(b) > 10)
    }

    @Test func petiteImage() {
        #expect(Empreinte(ImageGrise(largeur: 0, hauteur: 0, pixels: [])) == nil)
        #expect(Empreinte(ImageGrise(largeur: 1, hauteur: 1, pixels: [9]))?.bits == 0)
    }

    @Test func detecteurAvecGrace() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var d = DetecteurChangements(seuil: 6, grace: 60)
        let a = Empreinte(bits: 0), b = Empreinte(bits: 0xFF), presqueA = Empreinte(bits: 0b11)
        var r = d.observer(cle: "x", empreinte: a, maintenant: t0); #expect(!r)                          // première fois
        r = d.observer(cle: "x", empreinte: presqueA, maintenant: t0.addingTimeInterval(1)); #expect(!r)  // 2 bits
        r = d.observer(cle: "x", empreinte: b, maintenant: t0.addingTimeInterval(2)); #expect(r)
        r = d.observer(cle: "x", empreinte: a, maintenant: t0.addingTimeInterval(10)); #expect(!r)        // dans la grâce
        r = d.observer(cle: "x", empreinte: b, maintenant: t0.addingTimeInterval(100)); #expect(r)
        d.garder(seulement: [])
        r = d.observer(cle: "x", empreinte: a, maintenant: t0.addingTimeInterval(200)); #expect(!r)       // oubliée : 1re fois
    }
}

@Suite("Isolation des appels lents")
struct IsolationTests {
    @Test func disjoncteur() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var d = Disjoncteur(seuilEchecs: 2, pause: 300)
        #expect(!d.estOuvert("app", maintenant: t0))
        d.signalerEchec("app", maintenant: t0)
        #expect(!d.estOuvert("app", maintenant: t0))
        d.signalerEchec("app", maintenant: t0)
        #expect(d.estOuvert("app", maintenant: t0.addingTimeInterval(299)))
        #expect(d.appsEcartees(maintenant: t0.addingTimeInterval(1)) == ["app"])
        #expect(!d.estOuvert("app", maintenant: t0.addingTimeInterval(301)))
        d.signalerEchec("autre", maintenant: t0)
        d.signalerSucces("autre")
        d.signalerEchec("autre", maintenant: t0)
        #expect(!d.estOuvert("autre", maintenant: t0))   // le succès a remis le compteur à zéro
    }

    @Test func travailRapide() async {
        let file = DispatchQueue(label: "test.rapide")
        let r = await avecEcheance(2, file: file) { 21 * 2 }
        #expect(r == 42)
    }

    @Test func travailBloqueRendLaMain() async {
        let file = DispatchQueue(label: "test.lent")
        let debut = Date()
        let r: Int? = await avecEcheance(0.2, file: file) {
            Thread.sleep(forTimeInterval: 3)
            return 1
        }
        #expect(r == nil)
        #expect(Date().timeIntervalSince(debut) < 2)
    }

    @Test func plusieursAppelsConcurrents() async {
        let file = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let resultats = await withTaskGroup(of: Int?.self) { groupe in
            for i in 0..<20 {
                groupe.addTask { await avecEcheance(2, file: file) { i } }
            }
            var tous: [Int] = []
            for await r in groupe { if let r { tous.append(r) } }
            return tous.sorted()
        }
        #expect(resultats == Array(0..<20))
    }
}

@Suite("Analyse de l'encoche et barre secondaire")
struct AnalyseTests {
    @Test func iconesSousLEncoche() throws {
        let ecran = EcransTests.macBook
        let fenetres = [
            Cadre(x: 700, y: 0, largeur: 30, hauteur: 37),   // sous l'encoche
            Cadre(x: 900, y: 0, largeur: 30, hauteur: 37),   // à droite
            Cadre(x: 840, y: 0, largeur: 30, hauteur: 37),   // chevauche de 10 pt
            Cadre(x: 849, y: 0, largeur: 30, hauteur: 37),   // 1 pt : arrondi toléré
            Cadre(x: 700, y: 500, largeur: 30, hauteur: 37), // pas dans la barre
        ]
        let d = try #require(Analyse.encoche(ecran: ecran, fenetres: fenetres, hauteurEcranPrincipal: 982, hauteurParDefaut: 24))
        #expect(d.encoche == Cadre(x: 662, y: 0, largeur: 188, hauteur: 37))
        #expect(d.sousEncoche == [0, 2])
        #expect(d.aDesIconesCachees)
        #expect(d.largeurDroite == 662)
        #expect(Analyse.encoche(ecran: EcransTests.externe, fenetres: fenetres, hauteurEcranPrincipal: 982, hauteurParDefaut: 24) == nil)
    }

    @Test func encocheSurUnEcranSecondaire() throws {
        // MacBook à droite d'un écran principal 2560×1440 : Quartz décale y de 1440 - 982.
        let mb = EcranDecrit(id: 1, nom: "MB", cadre: Cadre(x: 2560, y: 0, largeur: 1512, hauteur: 982), hauteurBarre: 37,
                             largeurGaucheEncoche: 662, largeurDroiteEncoche: 662)
        let f = [Cadre(x: 2560 + 700, y: 458, largeur: 30, hauteur: 37), Cadre(x: 2560 + 700, y: 0, largeur: 30, hauteur: 37)]
        let d = try #require(Analyse.encoche(ecran: mb, fenetres: f, hauteurEcranPrincipal: 1440, hauteurParDefaut: 24))
        #expect(d.encoche.y == 458)
        #expect(d.sousEncoche == [0])
    }

    @Test func panneauSousLaFleche() {
        let m = MiseEnPagePanneau.calculer(tailles: Array(repeating: (24, 22), count: 3), ancreX: 1400,
                                           ecran: EcransTests.macBook, hauteurParDefaut: 24)
        #expect(m.cadre == Cadre(x: 1308, y: 907, largeur: 92, hauteur: 34))
        #expect(m.vignettes == [
            Cadre(x: 6, y: 6, largeur: 24, hauteur: 22),
            Cadre(x: 34, y: 6, largeur: 24, hauteur: 22),
            Cadre(x: 62, y: 6, largeur: 24, hauteur: 22),
        ])
    }

    @Test func panneauRameneDansLEcranEtALaLigne() {
        let petit = EcranDecrit(id: 9, nom: "petit", cadre: Cadre(x: 0, y: 0, largeur: 200, hauteur: 300), hauteurBarre: 24)
        let m = MiseEnPagePanneau.calculer(tailles: Array(repeating: (30, 22), count: 10), ancreX: 500,
                                           ecran: petit, hauteurParDefaut: 24)
        #expect(m.cadre.minX >= 6)
        #expect(m.cadre.maxX <= 194)
        #expect(m.cadre.largeur == 178)
        #expect(m.cadre.hauteur == 60)                 // deux lignes de cinq
        #expect(m.vignettes[0].y == 32)               // première ligne en haut
        #expect(m.vignettes[5].y == 6)
        #expect(m.vignettes[5].x == 6)
        // Aucune vignette ne sort du panneau.
        for v in m.vignettes { #expect(v.minX >= 0 && v.maxX <= m.cadre.largeur && v.minY >= 0 && v.maxY <= m.cadre.hauteur) }
    }

    @Test func panneauVide() {
        let m = MiseEnPagePanneau.calculer(tailles: [], ancreX: 1400, ecran: EcransTests.macBook, hauteurParDefaut: 24)
        #expect(m.vignettes.isEmpty)
        #expect(m.cadre.largeur == 40)
    }
}
