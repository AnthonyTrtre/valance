import AppKit
import ValanceCoeur

/// Icône « espace libre » : la place restante sur le disque de démarrage, relue chaque minute (et au réveil).
/// Même source que le Finder (`volumeAvailableCapacityForImportantUsage`, API publique) ; le menu liste aussi les
/// autres volumes locaux montés. Aucune autorisation, aucun réseau.
@MainActor
final class IndicateurDisque: NSObject, NSMenuDelegate {
    /// Nom d'enregistrement de la position : ne jamais le changer.
    static let nom = "valance.disque"

    private let item: NSStatusItem
    private var tache: Task<Void, Never>?
    var surReglages: (() -> Void)?

    override init() {
        // Au premier lancement, à droite de la flèche (positions comptées depuis le bord droit), donc visible.
        let d = UserDefaults.standard, cle = "NSStatusItem Preferred Position \(Self.nom)"
        if d.object(forKey: cle) == nil, let fleche = d.object(forKey: "NSStatusItem Preferred Position \(BarreStatut.nomFleche)") as? Double {
            d.set(max(0, fleche - 1), forKey: cle)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.nom
        super.init()
        item.button?.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Espace disque")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        actualiser()
        tache = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.actualiser()
            }
        }
    }

    func retirer() {
        tache?.cancel()
        NSStatusBar.system.removeStatusItem(item)
    }

    func actualiser() {
        guard let v = Self.volumes().first else { item.button?.title = " —"; return }
        let titre = " " + FormatDisque.court(v.libre)
        item.button?.attributedTitle = NSAttributedString(string: titre, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular),
            .foregroundColor: v.estPresquePlein ? NSColor.systemOrange : NSColor.labelColor,
        ])
        item.button?.toolTip = FormatDisque.detail(v)
        item.button?.setAccessibilityLabel("Espace libre : \(FormatDisque.court(v.libre))")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        actualiser()
        menu.removeAllItems()
        for v in Self.volumes() {
            let m = NSMenuItem(title: FormatDisque.detail(v), action: nil, keyEquivalent: "")
            m.image = NSImage(systemSymbolName: v.estPresquePlein ? "exclamationmark.triangle" : "internaldrive",
                              accessibilityDescription: nil)
            menu.addItem(m)
        }
        menu.addItem(.separator())
        menu.addItem(cible("Ouvrir le stockage dans Réglages Système…", #selector(ouvrirStockage)))
        menu.addItem(cible("Réglages de Valance…", #selector(ouvrirReglages)))
    }

    private func cible(_ titre: String, _ action: Selector) -> NSMenuItem {
        let m = NSMenuItem(title: titre, action: action, keyEquivalent: "")
        m.target = self
        return m
    }

    @objc private func ouvrirStockage() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(u) }
    }

    @objc private func ouvrirReglages() { surReglages?() }

    /// Disque de démarrage d'abord, puis les autres volumes locaux visibles (disques externes compris).
    static func volumes() -> [VolumeDecrit] {
        let cles: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeIsLocalKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: cles, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u -> (URL, VolumeDecrit)? in
            guard let r = try? u.resourceValues(forKeys: Set(cles)), r.volumeIsLocal == true, r.volumeIsBrowsable != false,
                  let total = r.volumeTotalCapacity, total > 0, let libre = r.volumeAvailableCapacityForImportantUsage else { return nil }
            return (u, VolumeDecrit(nom: r.volumeName ?? u.lastPathComponent, libre: libre, total: Int64(total)))
        }
        .sorted { a, b in a.0.path == "/" || (b.0.path != "/" && a.1.nom < b.1.nom) }
        .map(\.1)
    }
}
