import AppKit
import SocleCore
import Sparkle
import ValanceCoeur

/// Point d'entrée AppKit : une app de barre des menus sans fenêtre au démarrage (LSUIElement).
/// On n'utilise pas `MenuBarExtra` : il ne donne pas accès au bouton ni à la longueur de l'icône, or tout
/// Valance repose sur des `NSStatusItem` dont on règle la longueur.
/// Mises à jour intégrées (Sparkle) : archives signées EdDSA, vérifiées avant installation. Seul accès réseau de Valance.
@MainActor let miseAJour = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

@main
@MainActor
enum PointDEntree {
    static func main() {
        let app = NSApplication.shared
        let delegue = Delegue()
        app.delegate = delegue
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegue) { app.run() }
    }
}

@MainActor
final class Delegue: NSObject, NSApplicationDelegate {
    private(set) var controleur: Controleur?

    /// L'app sert d'hôte aux tests Xcode : on ne crée alors ni icône ni raccourci.
    static var sousTest: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.sousTest else { return }
        let autotest = ProcessInfo.processInfo.environment["VALANCE_AUTOTEST"] == "1"
        let magasin: any MagasinCleValeur
        if autotest { magasin = MagasinMemoire() } else { magasin = MagasinDefaults() }
        let c = Controleur(magasin: magasin)
        controleur = c
        c.demarrer()
        Journal.app.info("Valance démarré")
        if autotest { Autotest.lancer(c) } else { miseAJour.startUpdater() }   // pas de réseau pendant l'autotest
    }

    func applicationWillTerminate(_ notification: Notification) {
        controleur?.arreter()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Double-clic sur l'app déjà lancée (Finder, Spotlight) : ouvrir les réglages.
        controleur?.ouvrirReglages()
        return false
    }
}
