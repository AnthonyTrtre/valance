import AppKit
import SocleCore
import ValanceCoeur

/// Icône « Claude » : la part restante de la limite hebdomadaire de Claude, relue toutes les 10 minutes.
/// Valance ne touche à aucun jeton : il lance Claude Code (s'il est installé et connecté) en mode SDK et lui pose la
/// demande `get_usage`, sans message au modèle. C'est Claude Code qui contacte Anthropic, avec sa propre connexion.
@MainActor
final class IndicateurClaude: NSObject, NSMenuDelegate {
    /// Nom d'enregistrement de la position : ne jamais le changer.
    static let nom = "valance.claude"

    private let item: NSStatusItem
    private var tache: Task<Void, Never>?
    private var derniere: UtilisationClaude?
    private var releveA: Date?
    private var erreur: String?
    private var enCours = false
    var surReglages: (() -> Void)?

    override init() {
        // Au premier lancement, à droite de la flèche (positions comptées depuis le bord droit), donc visible.
        let d = UserDefaults.standard, cle = "NSStatusItem Preferred Position \(Self.nom)"
        if d.object(forKey: cle) == nil, let fleche = d.object(forKey: "NSStatusItem Preferred Position \(BarreStatut.nomFleche)") as? Double {
            d.set(max(0, fleche - 2), forKey: cle)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.nom
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        afficher()
        tache = Task { [weak self] in
            while !Task.isCancelled {
                await self?.relire()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    /// Version courte (« 71% », sans espaces) quand la place manque sous l'encoche.
    var compact = false { didSet { if compact != oldValue { afficher() } } }

    /// Éteint : largeur nulle, pas `isVisible` ni retrait, qui font oublier sa place à AppKit (macOS 26).
    var visible = true {
        didSet {
            item.length = visible ? NSStatusItem.variableLength : 0
            if visible { afficher() } else { item.button?.attributedTitle = NSAttributedString() }
        }
    }

    func retirer() {
        tache?.cancel()
        NSStatusBar.system.removeStatusItem(item)
    }

    func relire() async {
        guard !enCours else { return }
        enCours = true
        let resultat = await Task.detached(priority: .utility) { LecteurClaudeCode.utilisation() }.value
        enCours = false
        switch resultat {
        case .success(let u): derniere = u; erreur = nil; releveA = Date()
        case .failure(let e): erreur = e.message
        }
        afficher()
    }

    private func afficher() {
        guard visible, let b = item.button else { return }
        let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        image?.isTemplate = true
        b.image = image
        b.imagePosition = .imageLeading
        let texte: String, couleur: NSColor
        if let u = derniere {
            texte = compact ? "\(Int(u.restantSemaine.rounded()))%" : " \(Int(u.restantSemaine.rounded())) %"
            couleur = u.restantSemaine < 5 ? .systemRed : (u.bientotEpuise ? .systemOrange : .labelColor)
        } else {
            texte = " —"
            couleur = .secondaryLabelColor
        }
        b.attributedTitle = NSAttributedString(string: texte, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular),
            .foregroundColor: erreur != nil && derniere != nil ? NSColor.secondaryLabelColor : couleur,
        ])
        b.toolTip = derniere.map { "Claude : \(Int($0.restantSemaine.rounded())) % restants cette semaine" + Self.remise($0.remiseSemaine) }
            ?? erreur ?? "Claude : lecture en cours…"
        b.setAccessibilityLabel(b.toolTip)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if releveA.map({ Date().timeIntervalSince($0) > 120 }) ?? true { Task { await relire() } }
        menu.removeAllItems()
        if let u = derniere {
            menu.addItem(ligne("Semaine : \(Int(u.restantSemaine.rounded())) % restants (\(Int(u.semaine.rounded())) % utilisés)"))
            if let r = u.remiseSemaine { menu.addItem(ligne("Remise à zéro : \(Self.date(r))")) }
            if let c = u.cinqHeures {
                menu.addItem(ligne("5 heures : \(Int((100 - c).rounded())) % restants" + Self.remise(u.remiseCinqHeures)))
            }
            if let t = releveA {
                menu.addItem(ligne("Relevé à \(t.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))))"))
            }
        }
        if let e = erreur { menu.addItem(ligne(e)) }
        menu.addItem(.separator())
        menu.addItem(cible("Actualiser", #selector(actualiser)))
        menu.addItem(cible("Ouvrir l'utilisation sur claude.ai…", #selector(ouvrirClaude)))
        menu.addItem(cible("Réglages de Valance…", #selector(ouvrirReglages)))
    }

    private static func remise(_ d: Date?) -> String { d.map { " (remise \(date($0)))" } ?? "" }

    private static func date(_ d: Date) -> String {
        d.formatted(Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
            .locale(Locale(identifier: "fr_FR")))
    }

    private func ligne(_ titre: String) -> NSMenuItem { NSMenuItem(title: titre, action: nil, keyEquivalent: "") }

    private func cible(_ titre: String, _ action: Selector) -> NSMenuItem {
        let m = NSMenuItem(title: titre, action: action, keyEquivalent: "")
        m.target = self
        return m
    }

    @objc private func actualiser() { Task { await relire() } }
    @objc private func ouvrirClaude() {
        if let u = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(u) }
    }
    @objc private func ouvrirReglages() { surReglages?() }
}

struct ErreurClaude: Error {
    let message: String
}

/// Lance Claude Code en mode SDK (`-p`, entrées et sorties JSON), envoie `initialize` puis `get_usage`, lit la réponse
/// et l'arrête. Hors de l'acteur principal ; 30 s au plus.
enum LecteurClaudeCode {
    static func executable() -> URL? {
        let maison = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(maison)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(maison)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func utilisation() -> Result<UtilisationClaude, ErreurClaude> {
        guard let exe = executable() else {
            return .failure(ErreurClaude(message: "Claude Code introuvable : installez-le pour voir l'utilisation de Claude."))
        }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let entree = Pipe(), sortie = Pipe()
        p.standardInput = entree
        p.standardOutput = sortie
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            return .failure(ErreurClaude(message: "Claude Code ne démarre pas : \(error.localizedDescription)"))
        }
        let demandes = [#"{"type":"control_request","request_id":"init","request":{"subtype":"initialize"}}"#,
                        #"{"type":"control_request","request_id":"usage","request":{"subtype":"get_usage"}}"#]
        entree.fileHandleForWriting.write(Data((demandes.joined(separator: "\n") + "\n").utf8))
        let echeance = DispatchTime.now() + 30
        DispatchQueue.global().asyncAfter(deadline: echeance) { if p.isRunning { p.terminate() } }
        defer {
            if p.isRunning { p.terminate() }
            try? entree.fileHandleForWriting.close()
        }
        var tampon = Data()
        let lecture = sortie.fileHandleForReading
        while true {
            let morceau = lecture.availableData
            if morceau.isEmpty { break }
            tampon.append(morceau)
            while let fin = tampon.firstIndex(of: 0x0A) {
                let ligne = Data(tampon[..<fin])
                tampon.removeSubrange(...fin)
                guard let o = (try? JSONSerialization.jsonObject(with: ligne)) as? [String: Any],
                      o["type"] as? String == "control_response",
                      let r = o["response"] as? [String: Any], r["request_id"] as? String == "usage" else { continue }
                if r["subtype"] as? String != "success" {
                    return .failure(ErreurClaude(message: "Claude Code n'est pas connecté : lancez « claude auth login » dans le Terminal."))
                }
                return UtilisationClaude.lire(Data(ligne)).map { .success($0) }
                    ?? .failure(ErreurClaude(message: "Pas de limite hebdomadaire pour ce compte (clé d'API ?)."))
            }
        }
        return .failure(ErreurClaude(message: "Claude Code n'a pas répondu."))
    }
}
