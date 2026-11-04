import AppKit
import ApplicationServices
import ValanceCoeur

/// File dédiée aux appels d'Accessibilité. Un appel AX vers une app gelée bloque son appelant : ils ne passent
/// jamais par le fil principal, et chaque relevé a une échéance globale (`avecEcheance`).
let fileAccessibilite = DispatchQueue(label: "fr.anthony.valance.accessibilite", qos: .utility)
/// Menus des icônes (lecture, choix) : à part, pour ne pas attendre derrière un relevé de plusieurs secondes.
let fileMenus = DispatchQueue(label: "fr.anthony.valance.menus", qos: .userInitiated)

/// App interrogée (copie Sendable des infos de `NSRunningApplication`).
struct CibleAccessibilite: Sendable, Hashable {
    var pid: pid_t
    var bundle: String?
    var nom: String

    var cle: String { bundle ?? "pid:\(pid)" }
}

/// Une entrée du menu d'une icône, lue par l'Accessibilité pour être réaffichée par Valance.
struct EntreeMenu: Sendable {
    var titre: String
    var actif: Bool
    var coche: Bool
    var separateur: Bool
    var enfants: [EntreeMenu]
}

struct ReleveAccessibilite: Sendable {
    var elements: [ElementAccessible] = []
    /// Apps qui n'ont pas répondu dans le délai.
    var lentes: [String] = []
    /// Apps qui ont répondu (avec ou sans icône).
    var repondu: [String] = []
    /// Le budget total a été épuisé avant la fin de la liste.
    var interrompu = false
}

/// Lecture de la barre de chaque app : `AXUIElementCreateApplication` → `AXExtrasMenuBar` → enfants →
/// position, taille, titre, description, identifiant. API publique ; exige l'autorisation Accessibilité.
/// Rien ici n'est isolé à un acteur : ces fonctions tournent sur `fileAccessibilite`.
enum LecteurAccessibilite {
    /// Délai par message AX (secondes). Court : une app qui répond le fait en quelques millisecondes.
    static let delaiParMessage: Float = 0.25

    static var estAutorise: Bool { AXIsProcessTrusted() }

    /// Affiche la demande système (une seule fois par app ; ensuite il faut passer par Réglages Système).
    static func demanderAutorisation() -> Bool {
        let cle = "AXTrustedCheckOptionPrompt" as CFString   // valeur de kAXTrustedCheckOptionPrompt
        return AXIsProcessTrustedWithOptions([cle: true] as CFDictionary)
    }

    @MainActor static func cibles() -> [CibleAccessibilite] {
        let moi = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != moi && !$0.isTerminated && $0.processIdentifier > 0 }
            .map { CibleAccessibilite(pid: $0.processIdentifier, bundle: $0.bundleIdentifier,
                                      nom: $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)") }
    }

    static func lire(_ cibles: [CibleAccessibilite], budget: TimeInterval) -> ReleveAccessibilite {
        var r = ReleveAccessibilite()
        let debut = Date()
        for c in cibles {
            if Date().timeIntervalSince(debut) > budget { r.interrompu = true; break }
            let app = AXUIElementCreateApplication(c.pid)
            AXUIElementSetMessagingTimeout(app, delaiParMessage)
            var valeur: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &valeur)
            switch err {
            case .success:
                r.repondu.append(c.cle)
            case .cannotComplete:
                r.lentes.append(c.cle)
                continue
            default:
                r.repondu.append(c.cle)   // pas d'icône, ou app sans Accessibilité : réponse normale
                continue
            }
            guard let v = valeur, CFGetTypeID(v) == AXUIElementGetTypeID() else { continue }
            let barre = v as! AXUIElement   // type vérifié juste au-dessus
            for (rang, enfant) in enfants(de: barre).enumerated() {
                guard let cadre = cadre(de: enfant) else { continue }
                r.elements.append(ElementAccessible(pid: c.pid, bundle: c.bundle, nomApp: c.nom,
                                                    titre: texte(enfant, kAXTitleAttribute) ?? texte(enfant, kAXDescriptionAttribute),
                                                    identifiant: texte(enfant, kAXIdentifierAttribute),
                                                    cadre: cadre, rang: rang))
            }
        }
        return r
    }

    /// Clique sur l'icône `rang` de l'app `pid` (`AXPress`). Vrai si l'action a été acceptée.
    static func presser(pid: pid_t, rang: Int) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, delaiParMessage)
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &valeur) == .success,
              let v = valeur, CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
        let liste = enfants(de: v as! AXUIElement)
        guard liste.indices.contains(rang) else { return false }
        return AXUIElementPerformAction(liste[rang], kAXPressAction as CFString) == .success
    }

    /// Ouvre le menu de l'icône, le lit puis le referme. nil si l'icône n'ouvre pas de vrai menu (Electron et
    /// fenêtres surgissantes, qui ne répondent qu'à un vrai clic). Hors de l'écran, le menu s'ouvrirait hors de vue :
    /// Valance le réaffiche lui-même.
    static func lireMenu(pid: pid_t, rang: Int) -> [EntreeMenu]? {
        guard let item = item(pid: pid, rang: rang), let menu = ouvrirMenu(item) else { return nil }
        let entrees = lire(menu)
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        return entrees
    }

    /// Rouvre le menu et choisit l'entrée au bout du chemin (indices dans les menus et sous-menus).
    static func choisir(pid: pid_t, rang: Int, chemin: [Int]) -> Bool {
        guard let item = item(pid: pid, rang: rang), var menu = ouvrirMenu(item) else { return false }
        for (n, i) in chemin.enumerated() {
            let liste = enfants(de: menu)
            guard liste.indices.contains(i) else { AXUIElementPerformAction(menu, kAXCancelAction as CFString); return false }
            if n == chemin.count - 1 { return AXUIElementPerformAction(liste[i], kAXPressAction as CFString) == .success }
            guard let sous = enfants(de: liste[i]).first(where: { role(de: $0) == kAXMenuRole }) else { return false }
            menu = sous
        }
        return false
    }

    private static func item(pid: pid_t, rang: Int) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, delaiParMessage)
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &valeur) == .success,
              let v = valeur, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        let liste = enfants(de: v as! AXUIElement)
        return liste.indices.contains(rang) ? liste[rang] : nil
    }

    /// L'appui bloque tant que le menu est ouvert : il part sur une autre file, et l'on guette le menu.
    private static func ouvrirMenu(_ item: AXUIElement) -> AXUIElement? {
        nonisolated(unsafe) let cible = item
        DispatchQueue.global(qos: .userInitiated).async { _ = AXUIElementPerformAction(cible, kAXPressAction as CFString) }
        for _ in 0..<12 {
            usleep(60_000)
            if let m = enfants(de: item).first(where: { role(de: $0) == kAXMenuRole }), !enfants(de: m).isEmpty { return m }
        }
        return nil
    }

    private static func lire(_ menu: AXUIElement, profondeur: Int = 0) -> [EntreeMenu] {
        enfants(de: menu).map { e in
            let titre = texte(e, kAXTitleAttribute) ?? ""
            var actif: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXEnabledAttribute as CFString, &actif)
            let estActif = (actif as? Bool) ?? true
            let sous = profondeur < 3 ? enfants(de: e).first { role(de: $0) == kAXMenuRole } : nil
            return EntreeMenu(titre: titre, actif: estActif, coche: !(texte(e, kAXMenuItemMarkCharAttribute) ?? "").isEmpty,
                              separateur: titre.isEmpty && !estActif && sous == nil,
                              enfants: sous.map { lire($0, profondeur: profondeur + 1) } ?? [])
        }
    }

    private static func role(de e: AXUIElement) -> String? { texte(e, kAXRoleAttribute) }

    /// Bord droit (Quartz) des menus de l'app `pid` (Fichier, Édition…), pour savoir quelle place il reste aux icônes.
    static func finMenus(pid: pid_t) -> Cadre? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, delaiParMessage)
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &valeur) == .success,
              let v = valeur, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return enfants(de: v as! AXUIElement).compactMap(cadre(de:)).filter { !$0.estVide }.max { $0.maxX < $1.maxX }
    }

    // MARK: - Outils AX

    private static func enfants(de e: AXUIElement) -> [AXUIElement] {
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &valeur) == .success,
              let tableau = valeur as? [AnyObject] else { return [] }
        return tableau.compactMap { o in
            CFGetTypeID(o) == AXUIElementGetTypeID() ? (o as! AXUIElement) : nil
        }
    }

    private static func texte(_ e: AXUIElement, _ attribut: String) -> String? {
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribut as CFString, &valeur) == .success else { return nil }
        let s = valeur as? String
        return (s?.isEmpty ?? true) ? nil : s
    }

    private static func cadre(de e: AXUIElement) -> Cadre? {
        var p: CFTypeRef?, t: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &t) == .success,
              let pv = p, let tv = t,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(tv) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, taille = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &point),
              AXValueGetValue(tv as! AXValue, .cgSize, &taille) else { return nil }
        return Cadre(CGRect(origin: point, size: taille))
    }
}
