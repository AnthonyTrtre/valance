import Foundation
import Testing
@testable import ValanceCoeur

@Suite("Machine à états : masqué, révélé, repli")
struct MachineVisibiliteTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func demarrageMasque() {
        var m = MachineVisibilite()
        #expect(m.demarrer(maintenant: t0) == [.appliquer(.masquee)])
        #expect(m.echeanceRepli == nil)
    }

    @Test func demarrageRevelePlanifieLeRepli() {
        var m = MachineVisibilite(visibilite: .revelee, repliAutomatique: true, delai: 10)
        #expect(m.demarrer(maintenant: t0) == [.appliquer(.revelee), .planifierRepli(t(10))])
    }

    @Test func basculerReveleEtPlanifie() {
        var m = MachineVisibilite(delai: 10)
        #expect(m.traiter(.basculer, maintenant: t0) == [.appliquer(.revelee), .planifierRepli(t(10))])
        #expect(m.visibilite == .revelee)
        #expect(m.traiter(.basculer, maintenant: t(3)) == [.appliquer(.masquee), .annulerRepli])
        #expect(m.visibilite == .masquee)
        #expect(m.echeanceRepli == nil)
    }

    @Test func sansRepliAutomatique() {
        var m = MachineVisibilite(repliAutomatique: false)
        #expect(m.traiter(.basculer, maintenant: t0) == [.appliquer(.revelee)])
        #expect(m.traiter(.echeance(sourisDansBarre: false, menuOuvert: false), maintenant: t(100)) == [])
        #expect(m.visibilite == .revelee)
    }

    @Test func repliALEcheance() {
        var m = MachineVisibilite(delai: 5)
        _ = m.traiter(.reveler, maintenant: t0)
        #expect(m.traiter(.echeance(sourisDansBarre: false, menuOuvert: false), maintenant: t(5)) == [.appliquer(.masquee), .annulerRepli])
        #expect(m.visibilite == .masquee)
    }

    @Test func pasDeRepliSousLaSourisNiMenuOuvert() {
        var m = MachineVisibilite(delai: 5)
        _ = m.traiter(.reveler, maintenant: t0)
        #expect(m.traiter(.echeance(sourisDansBarre: true, menuOuvert: false), maintenant: t(5))
                == [.planifierRepli(t(5 + MachineVisibilite.relance))])
        #expect(m.traiter(.echeance(sourisDansBarre: false, menuOuvert: true), maintenant: t(7))
                == [.planifierRepli(t(7 + MachineVisibilite.relance))])
        #expect(m.visibilite == .revelee)
        #expect(m.traiter(.echeance(sourisDansBarre: false, menuOuvert: false), maintenant: t(9)) == [.appliquer(.masquee), .annulerRepli])
    }

    @Test func minuterieObsoleteIgnoree() {
        var m = MachineVisibilite(delai: 10)
        _ = m.traiter(.reveler, maintenant: t0)
        _ = m.traiter(.activite, maintenant: t(8))          // repousse à t(18)
        #expect(m.echeanceRepli == t(18))
        #expect(m.traiter(.echeance(sourisDansBarre: false, menuOuvert: false), maintenant: t(10)) == [])
        #expect(m.visibilite == .revelee)
    }

    @Test func activiteRepousseSansRaccourcir() {
        var m = MachineVisibilite(delai: 10)
        _ = m.traiter(.reveler, maintenant: t0)
        #expect(m.traiter(.activite, maintenant: t(4)) == [.planifierRepli(t(14))])
        #expect(m.traiter(.activite, maintenant: t(4)) == [])   // même échéance : rien à faire
        var masquee = MachineVisibilite()
        #expect(masquee.traiter(.activite, maintenant: t0) == [])
    }

    @Test func revelerDejaReveleProlonge() {
        var m = MachineVisibilite(delai: 10)
        _ = m.traiter(.reveler, maintenant: t0)
        #expect(m.traiter(.reveler, maintenant: t(5)) == [.planifierRepli(t(15))])
    }

    @Test func masquerDejaMasqueNeFaitRien() {
        var m = MachineVisibilite()
        #expect(m.traiter(.masquer, maintenant: t0) == [])
    }

    @Test func toutReveler() {
        var m = MachineVisibilite(delai: 10)
        #expect(m.traiter(.basculerTout, maintenant: t0) == [.appliquer(.toutRevele), .planifierRepli(t(10))])
        #expect(m.traiter(.basculerTout, maintenant: t(1)) == [.appliquer(.masquee), .annulerRepli])
        _ = m.traiter(.basculer, maintenant: t(2))            // révélé simple
        #expect(m.traiter(.basculerTout, maintenant: t(3)) == [.appliquer(.toutRevele), .planifierRepli(t(13))])
        #expect(m.traiter(.basculer, maintenant: t(4)) == [.appliquer(.masquee), .annulerRepli])
    }

    @Test func revelationTemporaire() {
        var m = MachineVisibilite(repliAutomatique: false)
        #expect(m.traiter(.revelerTemporairement(duree: 8), maintenant: t0) == [.appliquer(.revelee), .planifierRepli(t(8))])
        #expect(m.repliTemporaire)
        // Repli même sans repli automatique.
        #expect(m.traiter(.echeance(sourisDansBarre: false, menuOuvert: false), maintenant: t(8)) == [.appliquer(.masquee), .annulerRepli])
        #expect(!m.repliTemporaire)
    }

    @Test func revelationTemporaireNeRaccourcitPasUnRepliPlusLong() {
        var m = MachineVisibilite(delai: 30)
        _ = m.traiter(.reveler, maintenant: t0)
        #expect(m.traiter(.revelerTemporairement(duree: 5), maintenant: t(1)) == [])
        #expect(m.echeanceRepli == t(30))
        var sansAuto = MachineVisibilite(repliAutomatique: false)
        _ = sansAuto.traiter(.reveler, maintenant: t0)
        // Révélé à la main, sans repli : une règle ne doit pas le replier.
        #expect(sansAuto.traiter(.revelerTemporairement(duree: 5), maintenant: t(1)) == [])
    }

    @Test func basculerPendantRevelationTemporaireMasque() {
        var m = MachineVisibilite(repliAutomatique: false)
        _ = m.traiter(.revelerTemporairement(duree: 8), maintenant: t0)
        #expect(m.traiter(.basculer, maintenant: t(1)) == [.appliquer(.masquee), .annulerRepli])
    }

    @Test func reconfiguration() {
        var m = MachineVisibilite(repliAutomatique: false)
        _ = m.traiter(.reveler, maintenant: t0)
        #expect(m.traiter(.configurer(repliAutomatique: true, delai: 4), maintenant: t(1)) == [.planifierRepli(t(5))])
        #expect(m.traiter(.configurer(repliAutomatique: false, delai: 4), maintenant: t(2)) == [.annulerRepli])
        var masquee = MachineVisibilite()
        #expect(masquee.traiter(.configurer(repliAutomatique: true, delai: 1), maintenant: t0) == [])
        #expect(masquee.delai == MachineVisibilite.delaiMinimal)
    }

    @Test func bornesDuDelai() {
        #expect(MachineVisibilite.borner(0) == MachineVisibilite.delaiMinimal)
        #expect(MachineVisibilite.borner(1e9) == MachineVisibilite.delaiMaximal)
        #expect(MachineVisibilite.borner(.nan) == 10)
        #expect(MachineVisibilite(delai: -3).delai == MachineVisibilite.delaiMinimal)
    }

    /// Propriété : quelle que soit la suite d'événements, une échéance planifiée existe si et seulement si on
    /// est révélé avec repli (automatique ou temporaire), et jamais quand on est masqué.
    @Test func invariantSurSuitesAleatoires() {
        var g = GenerateurDeterministe(graine: 42)
        for _ in 0..<200 {
            var m = MachineVisibilite(visibilite: .masquee, repliAutomatique: g.booleen(), delai: Double(g.entier(1...30)))
            var horloge = t0
            _ = m.demarrer(maintenant: horloge)
            for _ in 0..<60 {
                horloge = horloge.addingTimeInterval(Double(g.entier(0...12)))
                let e: MachineVisibilite.Evenement
                switch g.entier(0...7) {
                case 0: e = .basculer
                case 1: e = .basculerTout
                case 2: e = .reveler
                case 3: e = .masquer
                case 4: e = .revelerTemporairement(duree: Double(g.entier(1...10)))
                case 5: e = .echeance(sourisDansBarre: g.booleen(), menuOuvert: g.entier(0...3) == 0)
                case 6: e = .activite
                default: e = .configurer(repliAutomatique: g.booleen(), delai: Double(g.entier(1...30)))
                }
                let effets = m.traiter(e, maintenant: horloge)
                if m.visibilite == .masquee { #expect(m.echeanceRepli == nil) }
                if m.echeanceRepli != nil { #expect(m.repliAutomatique || m.repliTemporaire) }
                if m.visibilite.estRevelee && m.repliAutomatique && !m.repliTemporaire { #expect(m.echeanceRepli != nil) }
                // Au plus un changement d'état par événement, et jamais deux planifications.
                #expect(effets.filter { if case .appliquer = $0 { true } else { false } }.count <= 1)
                #expect(effets.filter { if case .planifierRepli = $0 { true } else { false } }.count <= 1)
            }
        }
    }
}

/// Générateur pseudo-aléatoire reproductible (xorshift64*).
struct GenerateurDeterministe {
    var etat: UInt64
    init(graine: UInt64) { etat = graine == 0 ? 0x9E37_79B9_7F4A_7C15 : graine }
    mutating func suivant() -> UInt64 {
        etat ^= etat >> 12
        etat ^= etat << 25
        etat ^= etat >> 27
        return etat &* 2_685_821_657_736_338_717
    }
    mutating func entier(_ r: ClosedRange<Int>) -> Int {
        r.lowerBound + Int(suivant() % UInt64(r.upperBound - r.lowerBound + 1))
    }
    mutating func booleen() -> Bool { suivant() & 1 == 1 }
}
