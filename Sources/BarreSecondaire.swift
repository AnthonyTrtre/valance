import AppKit
import SwiftUI
import ValanceCoeur

/// Une vignette de la barre secondaire : l'image capturée de l'icône (si on l'a) et de quoi l'actionner.
struct Vignette: Identifiable {
    let id: String
    let nom: String
    let image: NSImage?
    let taille: CGSize
    let icone: IconeBarre
}

/// Panneau sous la barre des menus qui montre les icônes masquées sans les remettre dans la barre.
/// Non activant : il ne vole pas le focus de l'app au premier plan.
@MainActor
final class BarreSecondaire {
    private var panneau: NSPanel?
    private var moniteurClic: Any?
    var surChoix: ((IconeBarre) -> Void)?

    var estOuverte: Bool { panneau?.isVisible ?? false }

    func afficher(_ vignettes: [Vignette], message: String?, ancreX: Double, ecran: EcranDecrit) {
        fermer()
        let tailles = vignettes.map { (largeur: Double(max(16, $0.taille.width)), hauteur: Double(max(16, $0.taille.height))) }
        let mise = MiseEnPagePanneau.calculer(tailles: tailles, ancreX: ancreX, ecran: ecran,
                                              hauteurParDefaut: EcransMac.hauteurBarreParDefaut)
        var cadre = mise.cadre.cgRect
        if message != nil && vignettes.isEmpty {
            cadre.size.width = 320
            cadre.origin.x = min(cadre.origin.x, ecran.cadre.maxX - 326)
            cadre.size.height = 44
            cadre.origin.y = mise.cadre.maxY - 44
        }
        let vue = VueBarreSecondaire(vignettes: vignettes, cadres: mise.vignettes, taillePanneau: cadre.size,
                                     message: message) { [weak self] icone in
            self?.fermer()
            self?.surChoix?(icone)
        }
        let p = NSPanel(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.contentView = NSHostingView(rootView: vue)
        p.setFrame(cadre, display: true)
        p.orderFrontRegardless()
        panneau = p
        // Un clic ailleurs ferme le panneau (moniteur global de souris : aucune autorisation requise).
        moniteurClic = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.fermer()
        }
    }

    func fermer() {
        if let m = moniteurClic {
            NSEvent.removeMonitor(m)
            moniteurClic = nil
        }
        panneau?.orderOut(nil)
        panneau = nil
    }
}

struct VueBarreSecondaire: View {
    let vignettes: [Vignette]
    let cadres: [Cadre]
    let taillePanneau: CGSize
    let message: String?
    let choisir: (IconeBarre) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
            if let message, vignettes.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            ForEach(Array(vignettes.enumerated()), id: \.element.id) { i, v in
                let c = i < cadres.count ? cadres[i] : .zero
                Button { choisir(v.icone) } label: {
                    Group {
                        if let image = v.image {
                            Image(nsImage: image).resizable().interpolation(.high)
                        } else {
                            Text(String(v.nom.prefix(2))).font(.caption.bold())
                        }
                    }
                    .frame(width: c.largeur, height: c.hauteur)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(v.nom)
                // Les cadres ont leur origine en bas à gauche du panneau ; SwiftUI la veut en haut à gauche.
                .offset(x: c.x, y: taillePanneau.height - c.maxY)
            }
        }
        .frame(width: taillePanneau.width, height: taillePanneau.height)
    }
}
