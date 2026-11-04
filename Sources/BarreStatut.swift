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
        for item in [fleche, separateur] {
            item.button?.target = self
            item.button?.action = #selector(clic(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        fleche.button?.setAccessibilityLabel("Valance")
        separateur.button?.setAccessibilityLabel("Séparateur de Valance")
        separateur.button?.toolTip = "Séparateur de Valance : ⌘-glissez à sa gauche les icônes à masquer."
        separateur.button?.imagePosition = .imageOnly
        mettreAJourFleche(visibilite: .masquee, alerte: nil)
    }

    // MARK: - Section « toujours masquée »

    func activerToujoursMasque(_ actif: Bool) {
        if actif, toujoursMasque == nil {
            let item = NSStatusBar.system.statusItem(withLength: LongueurSeparateur.visible)
            item.autosaveName = Self.nomToujoursMasque
            item.button?.target = self
            item.button?.action = #selector(clic(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.image = Self.imageSeparateur
            item.button?.appearsDisabled = true
            item.button?.toolTip = "Second séparateur : les icônes à sa gauche ne se montrent qu'au ⌥-clic sur la flèche."
            item.button?.setAccessibilityLabel("Second séparateur de Valance")
            toujoursMasque = item
        } else if !actif, let item = toujoursMasque {
            NSStatusBar.system.removeStatusItem(item)
            toujoursMasque = nil
        }
    }

    // MARK: - Longueurs et apparence

    func appliquer(_ l: Longueurs, visibilite: Visibilite, afficherSeparateur: Bool) {
        // Élargir d'abord le séparateur qui masque, puis rétrécir l'autre : pas d'éclair d'icônes.
        let elargirAvant = (l.toujoursMasque ?? 0) > l.separateur
        if elargirAvant, let t = toujoursMasque, let lt = l.toujoursMasque { regler(t, longueur: lt, afficher: afficherSeparateur) }
        regler(separateur, longueur: l.separateur, afficher: afficherSeparateur)
        if !elargirAvant, let t = toujoursMasque, let lt = l.toujoursMasque { regler(t, longueur: lt, afficher: afficherSeparateur) }
    }

    private func regler(_ item: NSStatusItem, longueur: Double, afficher: Bool) {
        let court = longueur <= LongueurSeparateur.visible
        item.button?.image = (court && afficher) ? Self.imageSeparateur : nil
        item.length = CGFloat(max(0, longueur))
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
        for item in [fleche, separateur, toujoursMasque].compactMap({ $0 }) {
            NSStatusBar.system.removeStatusItem(item)
        }
        toujoursMasque = nil
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
