import Carbon.HIToolbox
import Foundation
import SocleCore
import ValanceCoeur

/// Raccourcis clavier globaux par `RegisterEventHotKey` (Carbon) : public, toujours pris en charge par macOS,
/// et **sans** autorisation d'Accessibilité ni de Surveillance de l'entrée (le système ne livre que la
/// combinaison enregistrée, jamais les autres frappes).
@MainActor
final class RaccourcisGlobaux {
    enum Action: UInt32 {
        case basculer = 1
        case toutReveler = 2
    }

    /// Appelé sur le fil principal quand un raccourci est pressé.
    static var surAction: ((Action) -> Void)?

    private var references: [Action: EventHotKeyRef] = [:]
    private var gestionnaire: EventHandlerRef?

    /// Enregistre un raccourci (ou le retire si nil). Renvoie faux si la combinaison est déjà prise par une
    /// autre app ou refusée par le système.
    @discardableResult
    func definir(_ raccourci: Raccourci?, pour action: Action) -> Bool {
        installerGestionnaire()
        if let ancienne = references.removeValue(forKey: action) {
            UnregisterEventHotKey(ancienne)
        }
        guard let r = raccourci, r.estValide else { return raccourci == nil }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: signatureValance, id: action.rawValue)
        let statut = RegisterEventHotKey(UInt32(r.codeTouche), r.modificateurs.carbon, id,
                                         GetApplicationEventTarget(), 0, &reference)
        guard statut == noErr, let reference else {
            Journal.app.error("Raccourci \(r.description, privacy: .public) refusé (\(statut))")
            return false
        }
        references[action] = reference
        return true
    }

    func toutRetirer() {
        for r in references.values { UnregisterEventHotKey(r) }
        references.removeAll()
        if let g = gestionnaire {
            RemoveEventHandler(g)
            gestionnaire = nil
        }
    }

    private func installerGestionnaire() {
        guard gestionnaire == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let statut = InstallEventHandler(GetApplicationEventTarget(), gestionnaireRaccourciCarbon, 1, &type, nil, &gestionnaire)
        if statut != noErr { Journal.app.error("InstallEventHandler a échoué (\(statut))") }
    }

    static func declencher(_ brut: UInt32) {
        guard let a = Action(rawValue: brut) else { return }
        surAction?(a)
    }
}

/// « VALA » : signature de nos raccourcis.
private let signatureValance: OSType = 0x5641_4C41

/// Rappel C appelé par le gestionnaire d'événements Carbon. Fonction globale, donc **non isolée** : elle ne
/// touche à rien de l'acteur principal et repasse la main par une tâche `@MainActor` explicite. (Une fermeture
/// créée dans un type `@MainActor` et appelée d'ailleurs planterait sous Swift 6, cf. Slipway.)
private func gestionnaireRaccourciCarbon(_ suivant: EventHandlerCallRef?, _ evenement: EventRef?,
                                         _ donnees: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evenement else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let statut = GetEventParameter(evenement, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard statut == noErr, id.signature == signatureValance else { return OSStatus(eventNotHandledErr) }
    let brut = id.id
    Task { @MainActor in RaccourcisGlobaux.declencher(brut) }
    return noErr
}
