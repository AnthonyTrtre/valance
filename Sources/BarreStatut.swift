import AppKit
import ValanceCoeur

/// Les icônes de Valance dans la barre, de droite à gauche : la flèche, le séparateur, et le second séparateur
/// (section « toujours masquée », facultatif). Les icônes que l'utilisateur ⌘-glisse à gauche du séparateur
/// sont poussées hors de l'écran quand on l'élargit. Aucune autorisation n'est nécessaire.
@MainActor
final class BarreStatut: NSObject {
    enum Clic { case principal, option, secondaire }

    /// Noms d'enregistrement des positions (`NSStatusItem Preferred Position <nom>`) : ne jamais les changer,
    /// sinon AppKit oublie où l'utilisateur a rangé nos icônes.
    static let nomFleche = "valance.fleche"
    static let nomSeparateur = "valance.separateur"
    static let nomToujoursMasque = "valance.toujoursMasque"

    let fleche: NSStatusItem
    let separateur: NSStatusItem
    private var toujoursMasque: NSStatusItem?
    private var toujoursMasqueCache: NSStatusItem?
    var surClic: ((Clic) -> Void)?

    private static let imageSeparateur: NSImage = BarreStatut.dessinerSeparateur()

    override init() {
        let barre = NSStatusBar.system
        // Créées dans cet ordre, chaque icône arrive à gauche de la précédente au premier lancement.
        fleche = barre.statusItem(withLength: NSStatusItem.squareLength)
        fleche.autosaveName = Self.nomFleche
        separateur = barre.statusItem(withLength: LongueurSeparateur.visible)
        separateur.autosaveName = Self.nomSeparateur
        super.init()
        fleche.button?.target = self
        fleche.button?.action = #selector(clic(_:))
        fleche.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        fleche.button?.setAccessibilityLabel("Valance")
        preparerSeparateur()
        mettreAJourFleche(visibilite: .masquee, alerte: nil)
    }

    private func preparerSeparateur() {
        separateur.button?.target = self
        separateur.button?.action = #selector(clic(_:))
        separateur.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        separateur.button?.setAccessibilityLabel("Séparateur de Valance")
        separateur.button?.toolTip = "Séparateur de Valance : les icônes à gauche de la flèche sont masquées."
        separateur.button?.imagePosition = .imageOnly
    }

    // MARK: - Section « toujours masquée »

    /// Désactivé, le second séparateur passe à une largeur nulle plutôt que d'être retiré ou caché : sous macOS 26,
    /// AppKit oublie la place d'une icône retirée ou cachée (`isVisible`), et la recréer la poserait n'importe où.
    func activerToujoursMasque(_ actif: Bool) {
        if actif, let item = toujoursMasqueCache {
            toujoursMasque = item
            toujoursMasqueCache = nil
        } else if actif, toujoursMasque == nil {
            // Première fois : tout à gauche (positions comptées depuis le bord droit), sinon toutes les icônes
            // masquées se retrouveraient « toujours cachées ».
            let d = UserDefaults.standard, cle = "NSStatusItem Preferred Position \(Self.nomToujoursMasque)"
            if d.object(forKey: cle) == nil { d.set(5000.0, forKey: cle) }
            let item = NSStatusBar.system.statusItem(withLength: LongueurSeparateur.repere)
            item.autosaveName = Self.nomToujoursMasque
            item.button?.target = self
            item.button?.action = #selector(clic(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            if let b = item.button { Self.ajouterRepere(b) }
            item.button?.toolTip = "Les icônes à gauche de l'œil barré restent cachées ; ⌥-clic sur la flèche pour les voir."
            item.button?.setAccessibilityLabel("Second séparateur de Valance")
            toujoursMasque = item
        } else if !actif, let item = toujoursMasque {
            reglerToujoursMasque(item, longueur: 0)
            toujoursMasqueCache = item
            toujoursMasque = nil
        }
    }

    // MARK: - Longueurs et apparence

    func appliquer(_ l: Longueurs, visibilite: Visibilite, afficherSeparateur: Bool) {
        // Élargir d'abord le séparateur qui masque, puis rétrécir l'autre : pas d'éclair d'icônes.
        let elargirAvant = (l.toujoursMasque ?? 0) > l.separateur
        if elargirAvant, let t = toujoursMasque, let lt = l.toujoursMasque { reglerToujoursMasque(t, longueur: lt) }
        regler(separateur, longueur: l.separateur, afficher: afficherSeparateur)
        if !elargirAvant, let t = toujoursMasque, let lt = l.toujoursMasque { reglerToujoursMasque(t, longueur: lt) }
    }

    private func regler(_ item: NSStatusItem, longueur: Double, afficher: Bool) {
        let court = longueur <= LongueurSeparateur.visible
        item.button?.image = (court && afficher) ? Self.imageSeparateur : nil
        item.length = CGFloat(max(0, longueur))
    }

    /// Le second séparateur garde un repère (œil barré) à son bord droit, même élargi : on voit où ⌘-glisser une
    /// icône pour la cacher toujours. Un bouton de barre centre son image : le repère est une vue collée à droite.
    private func reglerToujoursMasque(_ item: NSStatusItem, longueur: Double) {
        item.length = CGFloat(max(0, longueur))
        item.button?.subviews.first { $0 is NSImageView }?.isHidden = longueur <= 0
    }

    private static func ajouterRepere(_ bouton: NSStatusBarButton) {
        let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Toujours masquées")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        image?.isTemplate = true
        let vue = NSImageView(frame: NSRect(x: bouton.bounds.maxX - LongueurSeparateur.repere, y: 0,
                                            width: LongueurSeparateur.repere, height: bouton.bounds.height))
        vue.image = image
        vue.contentTintColor = .tertiaryLabelColor
        vue.autoresizingMask = [.minXMargin, .height]
        bouton.addSubview(vue)
    }

    func mettreAJourFleche(visibilite: Visibilite, alerte: String?) {
        let nom: String
        if alerte != nil {
            nom = "exclamationmark.triangle"
        } else {
            nom = visibilite.estRevelee ? "chevron.right" : "chevron.left"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: nom, accessibilityDescription: visibilite.estRevelee ? "Masquer" : "Révéler")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        fleche.button?.image = image
        fleche.button?.toolTip = alerte ?? (visibilite.estRevelee
            ? "Clic : masquer · ⌥-clic : tout révéler · clic droit : menu"
            : "Clic : révéler · ⌥-clic : tout révéler · clic droit : menu")
    }

    // MARK: - Positions

    /// Cadre d'une de nos icônes en Quartz (nil si AppKit ne l'a pas encore placée). Au lancement sur un MacBook seul,
    /// macOS donne d'abord un cadre vide (hauteur 0, bas de l'écran) : position inconnue, pas une vraie place.
    func cadreQuartz(_ item: NSStatusItem) -> Cadre? {
        guard let w = item.button?.window, w.frame.height >= 1 else { return nil }
        return Repere.versQuartz(Cadre(w.frame), hauteurEcranPrincipal: EcransMac.hauteurPrincipal)
    }

    var cadreFleche: Cadre? { cadreQuartz(fleche) }
    var cadreSeparateur: Cadre? { cadreQuartz(separateur) }
    var cadreToujoursMasque: Cadre? { toujoursMasque.flatMap { cadreQuartz($0) } }

    /// Cadre de la flèche en Cocoa (pour le survol et la barre secondaire).
    var cadreFlecheCocoa: Cadre? { fleche.button?.window.flatMap { $0.frame.height >= 1 ? Cadre($0.frame) : nil } }
    var ecranFleche: NSScreen? { fleche.button?.window?.screen }

    /// Numéros de nos propres fenêtres, à exclure de l'inventaire.
    var numerosFenetres: Set<UInt32> {
        Set([fleche, separateur, toujoursMasque].compactMap { $0?.button?.window?.windowNumber }.map { UInt32(truncatingIfNeeded: $0) })
    }

    // MARK: - Menu

    func afficherMenu(_ menu: NSMenu) {
        fleche.menu = menu
        fleche.button?.performClick(nil)
        fleche.menu = nil
    }

    @objc private func clic(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            surClic?(.secondaire)
        } else if e?.modifierFlags.contains(.option) == true {
            surClic?(.option)
        } else {
            surClic?(.principal)
        }
    }

    func retirer() {
        for item in [fleche, separateur, toujoursMasque, toujoursMasqueCache].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(item)
        }
        toujoursMasque = nil
        toujoursMasqueCache = nil
    }

    /// Trait vertical discret. Créé hors de l'acteur principal : AppKit peut appeler le dessin sur un autre fil.
    nonisolated private static func dessinerSeparateur() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1, width: 1.5, height: 14), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
