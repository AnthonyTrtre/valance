import Dispatch
import Foundation

/// Coupe-circuit par app pour les lectures d'Accessibilité : une app qui ne répond pas (délai dépassé) est
/// mise de côté pendant `pause`, au-delà de `seuilEchecs` échecs consécutifs. Un succès remet le compteur à zéro.
public struct Disjoncteur: Sendable {
    public var seuilEchecs: Int
    public var pause: TimeInterval
    private var echecs: [String: Int] = [:]
    private var ouvertJusqua: [String: Date] = [:]

    public init(seuilEchecs: Int = 2, pause: TimeInterval = 300) {
        self.seuilEchecs = max(1, seuilEchecs)
        self.pause = pause
    }

    /// Vrai si l'app doit être sautée pour l'instant.
    public func estOuvert(_ cle: String, maintenant: Date) -> Bool {
        guard let fin = ouvertJusqua[cle] else { return false }
        return maintenant < fin
    }

    public mutating func signalerEchec(_ cle: String, maintenant: Date) {
        let n = (echecs[cle] ?? 0) + 1
        echecs[cle] = n
        if n >= seuilEchecs {
            ouvertJusqua[cle] = maintenant.addingTimeInterval(pause)
            echecs[cle] = 0
        }
    }

    public mutating func signalerSucces(_ cle: String) {
        echecs[cle] = nil
        ouvertJusqua[cle] = nil
    }

    public func appsEcartees(maintenant: Date) -> [String] {
        ouvertJusqua.filter { maintenant < $0.value }.map(\.key).sorted()
    }
}

/// Exécute un travail bloquant sur une file dédiée et rend la main au plus tard après `secondes`.
/// Si l'échéance tombe d'abord, renvoie nil ; le travail continue sur sa file et son résultat est jeté.
/// Sert aux appels d'Accessibilité, qui bloquent l'appelant quand l'app visée est gelée : le fil principal
/// n'attend jamais, et la tâche appelante non plus au-delà de l'échéance.
///
/// Les fermetures passées à la file sont `@Sendable` et créées ici, hors de tout acteur : elles peuvent tourner
/// sur une autre file sans violer l'isolation de Swift 6 (leçon de Slipway).
public func avecEcheance<T: Sendable>(_ secondes: Double, file: DispatchQueue,
                                      _ travail: @escaping @Sendable () -> T) async -> T? {
    let unique = ReponseUnique<T>()
    return await withCheckedContinuation { (suite: CheckedContinuation<T?, Never>) in
        unique.armer(suite)
        file.async { @Sendable in unique.rendre(travail()) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, secondes)) { @Sendable in
            unique.rendre(nil)
        }
    }
}

/// Garantit qu'une continuation n'est reprise qu'une fois, quel que soit le premier arrivé.
final class ReponseUnique<T: Sendable>: @unchecked Sendable {
    private let verrou = NSLock()
    private var suite: CheckedContinuation<T?, Never>?
    private var rendu = false

    func armer(_ s: CheckedContinuation<T?, Never>) {
        verrou.lock(); defer { verrou.unlock() }
        suite = s
    }

    func rendre(_ valeur: T?) {
        verrou.lock()
        guard !rendu, let s = suite else { verrou.unlock(); return }
        rendu = true
        suite = nil
        verrou.unlock()
        s.resume(returning: valeur)
    }
}
