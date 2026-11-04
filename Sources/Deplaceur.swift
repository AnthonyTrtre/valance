import CoreGraphics

/// ⌘-glisser simulé d'une icône de la barre (V6, remplace V4) : appui ⌘ sur l'icône, glisser en quelques pas,
/// relâcher sur la cible, puis curseur remis où il était. Événements publics `CGEvent` ; macOS les accepte si
/// Valance a l'Accessibilité. Ne sert que quand l'utilisateur change une section dans les réglages, jamais en tâche
/// de fond.
@MainActor
enum Deplaceur {
    static func glisser(de depart: CGPoint, a arrivee: CGPoint) async {
        let origine = CGEvent(source: nil)?.location ?? depart
        let source = CGEventSource(stateID: .hidSystemState)
        func poster(_ type: CGEventType, _ p: CGPoint, commande: Bool) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
            e.flags = commande ? .maskCommand : []
            e.post(tap: .cghidEventTap)
        }
        poster(.mouseMoved, depart, commande: false)
        await pause(40)
        poster(.leftMouseDown, depart, commande: true)
        await pause(150)   // macOS « décroche » l'icône
        let pas = 14
        for i in 1...pas {
            let t = Double(i) / Double(pas)
            poster(.leftMouseDragged, CGPoint(x: depart.x + (arrivee.x - depart.x) * t, y: depart.y + (arrivee.y - depart.y) * t),
                   commande: true)
            await pause(16)
        }
        await pause(120)
        poster(.leftMouseUp, arrivee, commande: true)
        await pause(60)
        CGWarpMouseCursorPosition(origine)
        poster(.mouseMoved, origine, commande: false)
    }

    private static func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
}
