import AppKit
import CoreGraphics
import ScreenCaptureKit
import SocleCore
import ValanceCoeur

/// Image capturée (CGImage est immuable ; l'enveloppe permet de la rendre à l'acteur principal).
struct ImageCapturee: @unchecked Sendable {
    let numero: UInt32
    let image: CGImage
    /// Taille en points de l'icône (pour l'affichage).
    let taille: CGSize
}

/// Captures **ponctuelles** des icônes par ScreenCaptureKit (`SCScreenshotManager`), jamais de flux continu :
/// l'indicateur de capture de macOS ne s'allume qu'un instant. Exige l'autorisation Enregistrement de l'écran,
/// demandée seulement quand l'utilisateur active la barre secondaire.
enum Captures {
    static var estAutorise: Bool { CGPreflightScreenCaptureAccess() }

    /// Affiche la demande système ; renvoie l'état actuel (souvent faux tant que l'app n'a pas été relancée).
    static func demanderAutorisation() -> Bool { CGRequestScreenCaptureAccess() }

    /// Capture chaque fenêtre d'icône demandée, même hors de l'écran (filtre « fenêtre indépendante »).
    static func capturer(numeros: [UInt32], echelle: Double) async -> [ImageCapturee] {
        guard estAutorise, !numeros.isEmpty else { return [] }
        let voulues = Set(numeros)
        let contenu: SCShareableContent
        do {
            contenu = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            Journal.app.error("ScreenCaptureKit : \(error.localizedDescription, privacy: .public)")
            return []
        }
        var resultat: [ImageCapturee] = []
        for w in contenu.windows where voulues.contains(w.windowID) {
            let filtre = SCContentFilter(desktopIndependentWindow: w)
            let config = SCStreamConfiguration()
            config.width = max(1, Int((w.frame.width * echelle).rounded()))
            config.height = max(1, Int((w.frame.height * echelle).rounded()))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filtre, configuration: config)
                resultat.append(ImageCapturee(numero: w.windowID, image: image, taille: w.frame.size))
            } catch {
                Journal.app.debug("Capture de la fenêtre \(w.windowID) impossible : \(error.localizedDescription, privacy: .public)")
            }
        }
        // Ordre demandé.
        let rang = Dictionary(uniqueKeysWithValues: numeros.enumerated().map { ($1, $0) })
        return resultat.sorted { (rang[$0.numero] ?? 0) < (rang[$1.numero] ?? 0) }
    }

    /// Image en niveaux de gris, pour l'empreinte (règle « signaler les changements »).
    static func niveauxDeGris(_ image: CGImage) -> ImageGrise? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w * h <= 1_000_000 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let ctx = CGContext(data: tampon.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? ImageGrise(largeur: w, hauteur: h, pixels: pixels) : nil
    }
}
