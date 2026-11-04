import AppKit
import ValanceCoeur

/// Parcours automatique lancé par la CI (`VALANCE_AUTOTEST=1`) : il exerce, dans la vraie app, les chemins qui
/// traversent des files (rappel de raccourci, notifications postées d'un autre fil, lecture d'Accessibilité sur
/// sa file, capture) pour qu'une violation d'isolation de Swift 6 plante **en CI** et pas chez l'utilisateur.
/// Les réglages sont alors gardés en mémoire (rien n'est écrit dans les préférences).
@MainActor
enum Autotest {
    nonisolated static var actif: Bool { ProcessInfo.processInfo.environment["VALANCE_AUTOTEST"] == "1" }

    static func lancer(_ c: Controleur) {
        Task { @MainActor in
            var echecs: [String] = []
            func verifier(_ condition: Bool, _ quoi: String) {
                journal((condition ? "ok    " : "ÉCHEC ") + quoi)
                if !condition { echecs.append(quoi) }
            }
            func attendre(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

            journal("début")
            await attendre(0.5)
            verifier(c.visibilite == .masquee, "démarrage masqué")

            c.evenement(.basculer)
            verifier(c.visibilite == .revelee, "clic : révélé")
            c.evenement(.basculerTout)
            verifier(c.visibilite == .toutRevele, "⌥-clic : tout révélé")
            c.evenement(.basculer)
            verifier(c.visibilite == .masquee, "clic : masqué")

            // Raccourci : même chemin que le rappel Carbon (tâche @MainActor créée hors du fil principal).
            DispatchQueue.global().async { @Sendable in
                Task { @MainActor in RaccourcisGlobaux.declencher(RaccourcisGlobaux.Action.basculer.rawValue) }
            }
            await attendre(0.5)
            verifier(c.visibilite == .revelee, "raccourci depuis une autre file : révélé")

            // Repli automatique court.
            c.modifier { $0.repliAutomatique = true; $0.delaiRepli = 2 }
            c.evenement(.masquer)
            c.evenement(.reveler)
            await attendre(3)
            verifier(c.visibilite == .masquee || c.sourisDansBarre() || FenetresMac.menuOuvert(), "repli automatique après 2 s")

            // Section toujours masquée, aller-retour.
            c.modifier { $0.sectionToujoursMasquee = true }
            c.evenement(.basculerTout)
            c.evenement(.basculer)
            c.modifier { $0.sectionToujoursMasquee = false }
            verifier(true, "section toujours masquée créée puis retirée")

            // Changement d'écran notifié depuis un autre fil.
            DispatchQueue.global().async { @Sendable in
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            }
            await attendre(0.5)
            verifier(!c.ecrans.isEmpty, "écrans décrits (\(c.ecrans.count))")

            // Accessibilité : lecture sur sa file avec échéance, même sans autorisation (réponses immédiates).
            let cibles = Array(LecteurAccessibilite.cibles().prefix(15))
            let releve = await avecEcheance(5, file: fileAccessibilite) { @Sendable in
                LecteurAccessibilite.lire(cibles, budget: 4)
            }
            verifier(releve != nil, "lecture d'Accessibilité isolée (\(cibles.count) apps, \(releve?.elements.count ?? 0) icônes)")
            c.modifier { $0.inventaireActive = true }
            c.actualiserInventaire()
            await attendre(0.5)
            c.modifier { $0.inventaireActive = false }

            // Capture : sans autorisation, renvoie vide sans planter.
            let images = await Captures.capturer(numeros: [1, 2, 3], echelle: 1)
            verifier(images.isEmpty || Captures.estAutorise, "capture sans autorisation : rien")

            // Barre secondaire (message d'autorisation) puis fermeture.
            c.modifier { $0.modeAffichage = .dessous }
            c.evenement(.masquer)
            c.basculerBarreSecondaire()
            await attendre(0.5)
            c.basculerBarreSecondaire()
            c.modifier { $0.modeAffichage = .auto }
            verifier(true, "barre secondaire ouverte puis fermée")

            // Fenêtre de réglages.
            c.ouvrirReglages()
            await attendre(1)
            verifier(c.fenetreReglagesOuverte, "réglages ouverts")
            c.fermerReglages()

            journal(echecs.isEmpty ? "AUTOTEST OK" : "AUTOTEST ÉCHEC : \(echecs.joined(separator: " ; "))")
        }
    }

    nonisolated static func journal(_ texte: String) {
        FileHandle.standardError.write(Data("VALANCE-AUTOTEST \(texte)\n".utf8))
    }
}
