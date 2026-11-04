import AppKit
import CoreGraphics
import ValanceCoeur

// Adaptateurs entre AppKit / CoreGraphics et les types purs de ValanceCoeur.

extension Cadre {
    init(_ r: CGRect) {
        self.init(x: Double(r.origin.x), y: Double(r.origin.y), largeur: Double(r.size.width), hauteur: Double(r.size.height))
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: largeur, height: hauteur) }
}

enum EcransMac {
    /// Hauteur standard de la barre, pour un écran dont la barre est masquée automatiquement.
    @MainActor static var hauteurBarreParDefaut: Double { Double(NSStatusBar.system.thickness) }

    /// Hauteur de l'écran principal (origine des deux repères).
    @MainActor static var hauteurPrincipal: Double { Double(NSScreen.screens.first?.frame.height ?? 0) }

    @MainActor static func decrire() -> [EcranDecrit] {
        NSScreen.screens.map { s in
            let numero = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let f = s.frame
            let hauteurBarre = max(0, Double(f.maxY - s.visibleFrame.maxY))
            return EcranDecrit(id: numero, nom: s.localizedName, cadre: Cadre(f), hauteurBarre: hauteurBarre,
                               largeurGaucheEncoche: s.auxiliaryTopLeftArea.map { Double($0.width) },
                               largeurDroiteEncoche: s.auxiliaryTopRightArea.map { Double($0.width) })
        }
    }
}

/// Lecture de la liste des fenêtres (API publique, sans autorisation pour les numéros et les cadres).
enum FenetresMac {
    static var niveauBarre: Int { Int(CGWindowLevelForKey(.statusWindow)) }
    static var niveauMenu: Int { Int(CGWindowLevelForKey(.popUpMenuWindow)) }

    /// Fenêtres d'un niveau donné ; cadres en Quartz.
    static func liste(niveau: Int, aLEcranSeulement: Bool = true) -> [FenetreBarre] {
        let options: CGWindowListOption = aLEcranSeulement ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return infos.compactMap { d in
            guard (d[kCGWindowLayer as String] as? NSNumber)?.intValue == niveau,
                  let numero = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bornes = d[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bornes as CFDictionary) else { return nil }
            return FenetreBarre(numero: numero, cadre: Cadre(r))
        }
    }

    /// Un menu (de n'importe quelle app) est-il ouvert ? On ne replie pas la barre sous un menu.
    static func menuOuvert() -> Bool { !liste(niveau: niveauMenu).isEmpty }
}

/// Préférences : `UserDefaults` vu comme un magasin clé → données.
final class MagasinDefaults: MagasinCleValeur {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func donnees(pour cle: String) -> Data? { defaults.data(forKey: cle) }
    func ecrire(_ d: Data?, pour cle: String) {
        if let d { defaults.set(d, forKey: cle) } else { defaults.removeObject(forKey: cle) }
    }
}
