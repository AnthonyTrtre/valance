import SwiftUI
import ValanceCoeur

/// Bande des réglages qui reproduit la barre : on fait glisser une icône, les autres s'écartent en direct, et la
/// vraie barre ne change qu'au lâcher (Valance ⌘-glisse alors l'icône à sa place). Les repères (œil barré, flèche)
/// bornent les zones : passer une icône de l'autre côté d'un repère change aussi sa zone.
struct VueOrdre: View {
    let controleur: Controleur

    private enum Jeton: Hashable, Identifiable {
        case icone(String)
        case repere(ValanceCoeur.Section)   // début de la zone
        var id: String {
            switch self {
            case .icone(let c): c
            case .repere(let s): "repère-\(s)"
            }
        }
    }

    @State private var ordre: [Jeton] = []
    @State private var images: [String: NSImage] = [:]
    @State private var tenu: Jeton?
    @State private var depart = 0
    @State private var decalage: CGFloat = 0

    private var rangeables: [IconeBarre] { controleur.icones.filter { $0.element != nil && !$0.estFixe } }
    private var signature: [String] { rangeables.map { "\($0.cle)|\($0.section)" } }

    var body: some View {
        GeometryReader { geo in
            let place = min(34, max(18, geo.size.width / CGFloat(max(ordre.count, 1))))
            HStack(spacing: 0) {
                ForEach(Array(ordre.enumerated()), id: \.element.id) { n, j in
                    vue(j, place: place)
                        .frame(width: place, height: 30)
                        .offset(x: tenu == j ? decalage : 0)
                        .zIndex(tenu == j ? 1 : 0)
                        .gesture(glisser(j, place: place), including: estIcone(j) ? .all : .none)
                }
            }
            .frame(width: geo.size.width, height: 34)
            // Sombre comme la barre : les captures de la vraie barre sont claires.
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16)))
            .environment(\.colorScheme, .dark)
        }
        .frame(height: 34)
        .disabled(controleur.rangementEnCours != nil)
        .onAppear { reconstruire() }
        .onChange(of: signature) { reconstruire() }
        .onChange(of: controleur.messageRangement) { reconstruire() }   // échec : on remontre l'ordre réel
        .task(id: signature) { images = controleur.apercus() }
    }

    @ViewBuilder private func vue(_ j: Jeton, place: CGFloat) -> some View {
        switch j {
        case .icone(let cle):
            let nom = rangeables.first { $0.cle == cle }?.nom ?? ""
            Group {
                if let i = images[cle] { Image(nsImage: i).resizable().scaledToFit() }
                else { Image(systemName: "app.dashed").resizable().scaledToFit() }
            }
            .frame(width: min(22, place - 6), height: 18)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(tenu == j ? Color.accentColor.opacity(0.25) : .clear))
            .scaleEffect(tenu == j ? 1.18 : 1)
            .shadow(radius: tenu == j ? 3 : 0)
            .help(nom)
            .contentShape(Rectangle())
        case .repere(let s):
            Image(systemName: s == .visible ? "chevron.left" : "eye.slash")
                .foregroundStyle(.secondary)
                .help(s == .visible ? "Flèche : à droite, toujours visible ; à gauche, visible au clic"
                                    : "À gauche de l'œil barré : toujours cachée")
        }
    }

    private func estIcone(_ j: Jeton) -> Bool { if case .icone = j { true } else { false } }

    private func glisser(_ j: Jeton, place: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { g in
                guard let ici = ordre.firstIndex(of: j) else { return }
                if tenu == nil { tenu = j; depart = ici }
                let cible = min(ordre.count - 1, max(0, depart + Int((g.translation.width / place).rounded())))
                if cible != ici {
                    withAnimation(.spring(duration: 0.22)) {
                        ordre.move(fromOffsets: [ici], toOffset: cible > ici ? cible + 1 : cible)
                    }
                }
                decalage = g.translation.width - CGFloat(cible - depart) * place
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.22)) { decalage = 0 }
                let fin = ordre.firstIndex(of: j)
                tenu = nil
                if let fin, fin != depart { appliquer(j, a: fin) }
            }
    }

    /// Zone d'une place : celle du dernier repère à sa gauche.
    private func zone(_ n: Int) -> ValanceCoeur.Section {
        for k in stride(from: n, through: 0, by: -1) { if case .repere(let s) = ordre[k] { return s } }
        return controleur.reglages.sectionToujoursMasquee ? .toujoursMasquee : .masquee
    }

    private func icone(_ n: Int) -> IconeBarre? {
        guard ordre.indices.contains(n), case .icone(let c) = ordre[n] else { return nil }
        return rangeables.first { $0.cle == c }
    }

    /// Au lâcher : contre la voisine de droite dans la zone, sinon celle de gauche, sinon seule dans sa zone.
    private func appliquer(_ j: Jeton, a n: Int) {
        guard let tenue = icone(n) else { return }
        if let d = icone(n + 1) { controleur.ordonner(tenue, pres: d, apres: false) }
        else if let g = icone(n - 1) { controleur.ordonner(tenue, pres: g, apres: true) }
        else { controleur.ranger(tenue, vers: zone(n)) }
    }

    private func reconstruire() {
        guard tenu == nil, controleur.rangementEnCours == nil else { return }
        var r: [Jeton] = []
        let zones: [ValanceCoeur.Section] = controleur.reglages.sectionToujoursMasquee ? [.toujoursMasquee, .masquee, .visible]
                                                                                       : [.masquee, .visible]
        for (k, s) in zones.enumerated() {
            if k > 0 { r.append(.repere(s)) }
            r += rangeables.filter { $0.section == s }.map { .icone($0.cle) }
        }
        ordre = r
    }
}
