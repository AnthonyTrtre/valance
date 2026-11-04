import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Raccourcis")
struct RaccourciTests {
    @Test func parDefaut() {
        let r = Raccourci.parDefaut
        #expect(r.description == "⌃⌥⌘V")
        #expect(r.estValide)
        #expect(r.modificateurs.carbon == 0x0100 | 0x0800 | 0x1000)
    }

    @Test func masquesCarbonEtCocoa() {
        let tous: Modificateurs = [.commande, .majuscule, .option, .controle]
        #expect(tous.carbon == 0x1B00)
        let cocoa: UInt = (1 << 17) | (1 << 20) | (1 << 8)   // ⇧⌘ + un bit étranger (ignoré)
        #expect(Modificateurs(drapeauxCocoa: cocoa) == [.majuscule, .commande])
        #expect(Modificateurs(drapeauxCocoa: 0) == [])
        #expect(tous.symboles == "⌃⌥⇧⌘")
    }

    @Test func validite() {
        #expect(!Raccourci(codeTouche: 0x00, modificateurs: []).estValide)            // lettre seule
        #expect(!Raccourci(codeTouche: 0x00, modificateurs: [.majuscule]).estValide)  // ⇧A
        #expect(Raccourci(codeTouche: 0x00, modificateurs: [.option]).estValide)
        #expect(Raccourci(codeTouche: 0x7A, modificateurs: []).estValide)             // F1 seule
        #expect(!Raccourci(codeTouche: 0x37, modificateurs: [.commande]).estValide)   // ⌘ seule
    }

    @Test func nomsDesTouches() {
        #expect(Raccourci(codeTouche: 0x31, modificateurs: [.controle]).description == "⌃Espace")
        #expect(Raccourci(codeTouche: 0x6F, modificateurs: []).description == "F12")
        #expect(Raccourci(codeTouche: 0x7B, modificateurs: [.commande]).description == "⌘←")
        #expect(NomsTouches.nom(0xFF) == "touche 255")
    }

    @Test func libelleDeLaDispositionReelle() {
        // AZERTY : la touche physique « A » ANSI porte un Q.
        let r = Raccourci(codeTouche: 0x00, modificateurs: [.option, .commande], libelle: "q")
        #expect(r.description == "⌥⌘Q")
        // Le libellé n'écrase pas les noms spéciaux.
        #expect(Raccourci(codeTouche: 0x31, modificateurs: [.option], libelle: " ").description == "⌥Espace")
        // L'égalité ignore le libellé.
        #expect(r == Raccourci(codeTouche: 0x00, modificateurs: [.commande, .option]))
        #expect(Set([r, Raccourci(codeTouche: 0x00, modificateurs: [.commande, .option])]).count == 1)
    }

    @Test func allerRetourJSON() throws {
        let r = Raccourci(codeTouche: 0x0B, modificateurs: [.controle, .commande], libelle: "b")
        let d = try JSONEncoder().encode(r)
        let r2 = try JSONDecoder().decode(Raccourci.self, from: d)
        #expect(r2 == r)
        #expect(r2.libelle == "b")
    }
}

@Suite("Réglages et persistance")
struct ReglagesTests {
    @Test func clesAbsentesDonnentLesValeursParDefaut() throws {
        let r = try JSONDecoder().decode(Reglages.self, from: Data("{}".utf8))
        #expect(r == Reglages())
        #expect(r.raccourci == .parDefaut)
    }

    @Test func raccourciEffaceResteEfface() throws {
        let r = try JSONDecoder().decode(Reglages.self, from: Data(#"{"raccourci": null}"#.utf8))
        #expect(r.raccourci == nil)
        var e = Reglages()
        e.raccourci = nil
        let d = try JSONEncoder().encode(e)
        #expect(try JSONDecoder().decode(Reglages.self, from: d).raccourci == nil)
    }

    @Test func versionFutureAvecCleInconnue() throws {
        let json = #"{"delaiRepli": 25, "nouveauReglage": true, "regles": {"com.exemple": {"placement": "visible", "inconnu": 1}}}"#
        let r = try JSONDecoder().decode(Reglages.self, from: Data(json.utf8))
        #expect(r.delaiRepli == 25)
        #expect(r.regles["com.exemple"]?.placement == .visible)
        #expect(r.regles["com.exemple"]?.dansBarreSecondaire == true)
    }

    @Test func placementInconnuDevientLibre() throws {
        let r = try JSONDecoder().decode(RegleApp.self, from: Data(#"{"placement": "ailleurs"}"#.utf8))
        #expect(r.placement == .libre)
        #expect(r.estParDefaut)
    }

    @Test func normalisation() {
        var r = Reglages()
        r.delaiRepli = 0.1
        r.dureeSignalement = 1000
        r.raccourci = Raccourci(codeTouche: 0x00, modificateurs: [])        // invalide
        r.raccourciToutReveler = Raccourci(codeTouche: 0x01, modificateurs: [.option])
        let n = r.normalises()
        #expect(n.delaiRepli == MachineVisibilite.delaiMinimal)
        #expect(n.dureeSignalement == 60)
        #expect(n.raccourci == nil)
        #expect(n.raccourciToutReveler != nil)
        var doublon = Reglages()
        doublon.raccourciToutReveler = .parDefaut                          // même que le principal
        #expect(doublon.normalises().raccourciToutReveler == nil)
    }

    @Test func persistanceAllerRetour() {
        let p = Persistance(magasin: MagasinMemoire())
        #expect(p.chargerReglages() == Reglages())
        var r = Reglages()
        r.delaiRepli = 42
        r.sectionToujoursMasquee = true
        r.regles["com.exemple"] = RegleApp(placement: .toujoursMasquee, dansBarreSecondaire: false)
        p.enregistrer(r)
        #expect(p.chargerReglages() == r)
    }

    @Test func donneesCorrompues() {
        let m = MagasinMemoire()
        m.ecrire(Data("pas du json".utf8), pour: Persistance.cleReglages)
        #expect(Persistance(magasin: m).chargerReglages() == Reglages())
    }

    @Test func etatMemorise() {
        let p = Persistance(magasin: MagasinMemoire())
        var r = Reglages()
        #expect(p.visibiliteDeDepart(r) == .masquee)       // rien d'enregistré
        p.memoriser(.revelee)
        #expect(p.visibiliteDeDepart(r) == .revelee)
        p.memoriser(.toutRevele)
        #expect(p.visibiliteDeDepart(r) == .revelee)       // jamais « tout révélé » au démarrage
        r.memoriserEtat = false
        #expect(p.visibiliteDeDepart(r) == .masquee)
        p.magasin.ecrire(Data("n'importe".utf8), pour: Persistance.cleVisibilite)
        r.memoriserEtat = true
        #expect(p.visibiliteDeDepart(r) == .masquee)
    }
}
