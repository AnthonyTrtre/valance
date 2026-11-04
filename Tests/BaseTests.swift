import Foundation
import Testing
import ValanceCoeur
@testable import Valance

/// Tests de la coque d'app (la logique pure est testée dans ValanceKit, y compris sous Linux).
@MainActor
@Suite struct CoqueTests {
    @Test func magasinDefaultsAllerRetour() throws {
        let nom = "fr.anthony.valance.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: nom))
        defer { defaults.removePersistentDomain(forName: nom) }
        let p = Persistance(magasin: MagasinDefaults(defaults))
        var r = Reglages()
        r.delaiRepli = 33
        r.raccourci = nil
        p.enregistrer(r)
        #expect(p.chargerReglages() == r)
        p.memoriser(.revelee)
        #expect(p.visibiliteDeDepart(r) == .revelee)
        MagasinDefaults(defaults).ecrire(nil, pour: Persistance.cleVisibilite)
        #expect(p.visibiliteDeDepart(r) == .masquee)
    }

    @Test func controleurSansBarreModifieEtPersiste() {
        let magasin = MagasinMemoire()
        let c = Controleur(magasin: magasin)
        #expect(c.visibilite == .masquee)
        c.modifier { $0.delaiRepli = 0.5 }      // normalisé
        #expect(c.reglages.delaiRepli == 2)
        #expect(Persistance(magasin: magasin).chargerReglages().delaiRepli == 2)
        c.definirRegle(RegleApp(placement: .visible), pour: "com.exemple")
        #expect(c.regle(pour: "com.exemple").placement == .visible)
        c.definirRegle(RegleApp(), pour: "com.exemple")   // règle par défaut : effacée
        #expect(c.reglages.regles.isEmpty)
    }

    @Test func conversionCGRect() {
        let r = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(Cadre(r).cgRect == r)
    }
}
