import AppKit
import Observation
import SocleBarreDeMenus
import SocleCore
import SwiftUI
import ValanceCoeur

/// Relie la logique pure (ValanceCoeur) aux adaptateurs macOS et expose l'état aux réglages SwiftUI.
/// Tout vit sur le fil principal, sauf les lectures d'Accessibilité (file dédiée, échéance) et les captures
/// (tâche asynchrone non isolée).
@MainActor
@Observable
final class Controleur {
    private(set) var reglages: Reglages
    private(set) var visibilite: Visibilite = .masquee
    private(set) var ecrans: [EcranDecrit] = []
    private(set) var diagnosticsEncoche: [DiagnosticEncoche] = []
    /// Le séparateur a été ⌘-glissé à droite de la flèche : on refuse de masquer.
    private(set) var ordreInvalide = false
    /// La flèche est sous l'encoche (trop d'icônes visibles sur un écran à encoche) : on ne peut plus cliquer dessus.
    private(set) var flecheCachee = false
    private(set) var raccourciRefuse: [RaccourcisGlobaux.Action] = []
    private(set) var ouvertureALaConnexion = false
    // Inventaire (Accessibilité)
    private(set) var accessibiliteAccordee = false
    private(set) var icones: [IconeBarre] = []
    /// Rangement (V6) : icône en cours de déplacement et dernier message d'échec.
    private(set) var rangementEnCours: String?
    private(set) var messageRangement: String?
    /// Rangements impossibles sur l'écran actuel (icône sous l'encoche) : refaits dès qu'un écran change.
    private(set) var enAttente: [String: ValanceCoeur.Section] = {
        let brut = UserDefaults.standard.dictionary(forKey: "valance.enAttente.v1") as? [String: String] ?? [:]
        return brut.compactMapValues { ValanceCoeur.Section(rawValue: $0) }
    }() {
        didSet { UserDefaults.standard.set(enAttente.mapValues(\.rawValue), forKey: "valance.enAttente.v1") }
    }
    static let attenteEcran = "attente d'un écran plus large"
    private(set) var appsEcartees: [String] = []
    private(set) var dernierReleve: Date?
    private(set) var releveEnCours = false
    // Barre secondaire (Enregistrement de l'écran)
    private(set) var captureAccordee = false

    @ObservationIgnored private var machine: MachineVisibilite
    @ObservationIgnored private let persistance: Persistance
    @ObservationIgnored private var barre: BarreStatut?
    @ObservationIgnored private var disque: IndicateurDisque?
    @ObservationIgnored private var relaisMenu: RelaisMenu?
    @ObservationIgnored private let raccourcis = RaccourcisGlobaux()
    @ObservationIgnored private let barreSecondaire = BarreSecondaire()
    @ObservationIgnored private var tacheRepli: Task<Void, Never>?
    @ObservationIgnored private var tachesFond: [Task<Void, Never>] = []
    @ObservationIgnored private var observateurs: [NSObjectProtocol] = []
    @ObservationIgnored private var moniteurSurvol: Any?
    @ObservationIgnored private var debutSurvol: Date?
    @ObservationIgnored private var fenetreReglages: NSWindow?
    @ObservationIgnored private var disjoncteur = Disjoncteur()
    @ObservationIgnored private var detecteur = DetecteurChangements()
    @ObservationIgnored private var cacheImages: [String: ImageCapturee] = [:]
    @ObservationIgnored private var fileRangement: [(cle: String, vers: ValanceCoeur.Section)] = []

    init(magasin: any MagasinCleValeur = MagasinDefaults()) {
        persistance = Persistance(magasin: magasin)
        let r = persistance.chargerReglages()
        reglages = r
        machine = MachineVisibilite(visibilite: persistance.visibiliteDeDepart(r),
                                    repliAutomatique: r.repliAutomatique, delai: r.delaiRepli)
    }

    // MARK: - Cycle de vie

    func demarrer() {
        let b = BarreStatut()
        b.surClic = { [weak self] clic in self?.clic(clic) }
        barre = b
        b.activerToujoursMasque(reglages.sectionToujoursMasquee)
        RaccourcisGlobaux.surAction = { [weak self] action in
            switch action {
            case .basculer: self?.basculerSelonPlace()
            case .toutReveler: self?.evenement(.basculerTout)
            }
        }
        appliquerRaccourcis()
        barreSecondaire.surChoix = { [weak self] icone in self?.activer(icone) }
        actualiserEcrans()
        OuvertureALaConnexion.activerAuPremierLancement()
        ouvertureALaConnexion = OuvertureALaConnexion.active
        rafraichirAutorisations()
        configurerSurvol()
        reprendreAttente(dans: 8)
        executer(machine.demarrer(maintenant: Date()))
        observerSysteme()
        if reglages.inventaireActive { lancerInventairePeriodique() }
        afficherDisque(reglages.afficherDisque)
    }

    private func afficherDisque(_ oui: Bool) {
        // Caché plutôt que retiré : il garde sa place dans la barre.
        if oui, disque == nil {
            disque = IndicateurDisque()
            disque?.surReglages = { [weak self] in self?.ouvrirReglages() }
        } else {
            disque?.visible = oui
        }
    }

    func arreter() {
        tacheRepli?.cancel()
        tachesFond.forEach { $0.cancel() }
        tachesFond.removeAll()
        for o in observateurs {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observateurs.removeAll()
        raccourcis.toutRetirer()
        disque?.retirer()
        disque = nil
        barreSecondaire.fermer()
        if let m = moniteurSurvol { NSEvent.removeMonitor(m) }
        moniteurSurvol = nil
    }

    // MARK: - Événements

    func evenement(_ e: MachineVisibilite.Evenement) {
        executer(machine.traiter(e, maintenant: Date()))
    }

    private func clic(_ c: BarreStatut.Clic) {
        switch c {
        case .principal:
            basculerSelonPlace()
        case .option:
            barreSecondaire.fermer()
            evenement(.basculerTout)
        case .secondaire:
            barre?.afficherMenu(construireMenu())
        }
    }

    private func executer(_ effets: [MachineVisibilite.Effet]) {
        for effet in effets {
            switch effet {
            case .appliquer(let v):
                visibilite = v
                // La flèche est la frontière : une icône ⌘-glissée entre le séparateur et elle doit être masquée aussi.
                if !v.estRevelee, rangementEnCours == nil, accessibiliteAccordee, iconesEntreSeparateurEtFleche() {
                    masquerCellesDeGauche()
                } else {
                    appliquerLongueurs()
                }
                persistance.memoriser(v)
                if v.estRevelee {
                    barreSecondaire.fermer()
                    // Les icônes révélées sont à leur place une fraction de seconde plus tard.
                    differer(0.4) { [weak self] in
                        self?.analyserEncoche()
                        if self?.reglages.inventaireActive == true { self?.actualiserInventaire() }
                    }
                }
            case .planifierRepli(let date):
                tacheRepli?.cancel()
                tacheRepli = Task { @MainActor [weak self] in
                    let attente = max(0, date.timeIntervalSinceNow)
                    try? await Task.sleep(for: .milliseconds(Int(attente * 1000) + 20))
                    guard !Task.isCancelled, let self else { return }
                    self.evenement(.echeance(sourisDansBarre: self.sourisDansBarre(), menuOuvert: FenetresMac.menuOuvert()))
                }
            case .annulerRepli:
                tacheRepli?.cancel()
                tacheRepli = nil
            }
        }
    }

    /// Applique les longueurs de la visibilité courante, sauf si l'ordre de nos icônes rendrait la flèche
    /// inaccessible.
    private func appliquerLongueurs() {
        guard let barre else { return }
        let largeurs = ecrans.map(\.cadre.largeur)
        var cible = visibilite
        // Pendant un rangement, tout reste à l'écran (le repli éventuel s'appliquera après).
        if rangementEnCours != nil { cible = .toutRevele }
        let ordreOK = Disposition.ordreValide(xFleche: barre.cadreFleche?.minX, xSeparateur: barre.cadreSeparateur?.minX,
                                              xToujoursMasque: reglages.sectionToujoursMasquee ? barre.cadreToujoursMasque?.minX : nil)
        ordreInvalide = !ordreOK
        if !ordreOK && cible != .toutRevele {
            // On garde tout à l'écran tant que l'utilisateur n'a pas remis le séparateur à gauche de la flèche.
            cible = .toutRevele
            Journal.app.notice("Séparateur à droite de la flèche : masquage suspendu (flèche \(barre.cadreFleche.map { "\($0)" } ?? "?", privacy: .public), séparateur \(barre.cadreSeparateur.map { "\($0)" } ?? "?", privacy: .public))")
        }
        let l = Disposition.longueurs(pour: cible, sectionToujoursMasquee: reglages.sectionToujoursMasquee,
                                      afficherSeparateur: rangementEnCours != nil,
                                      longueurMasquage: LongueurSeparateur.pourMasquer(largeursEcrans: largeurs))
        barre.appliquer(l, visibilite: cible, afficherSeparateur: rangementEnCours != nil)
        barre.mettreAJourFleche(visibilite: visibilite, alerte: alerte)
    }

    /// Les icônes posées entre le séparateur et la flèche passent à gauche du séparateur (⌘-glisser, comme
    /// Réglages → Icônes) ; le masquage s'applique à la fin du rangement.
    private func masquerCellesDeGauche() {
        let avant = dernierReleve
        actualiserInventaire()
        Task { @MainActor [weak self] in
            for _ in 0..<30 where self?.dernierReleve == avant { try? await Task.sleep(for: .milliseconds(100)) }
            guard let self, let barre = self.barre, let s = barre.cadreSeparateur.map(self.ref), let f = barre.cadreFleche.map(self.ref) else { return }
            let entre = self.icones.filter { $0.element != nil && $0.cadre.milieuX > s.maxX && $0.cadre.milieuX < f.minX }
            Journal.app.info("Icônes à gauche de la flèche à masquer : \(entre.count, privacy: .public)")
            if entre.isEmpty { self.appliquerLongueurs() }
            for i in entre { self.ranger(i, vers: .masquee) }
        }
    }

    /// Une icône d'une autre app se trouve-t-elle entre notre séparateur et la flèche, sur la même barre ?
    private func iconesEntreSeparateurEtFleche() -> Bool {
        guard let barre, let s = barre.cadreSeparateur, let f = barre.cadreFleche, s.maxX <= f.minX + 1 else { return false }
        let nos = barre.numerosFenetres
        return FenetresMac.liste(niveau: FenetresMac.niveauBarre, aLEcranSeulement: false).contains { w in
            !nos.contains(w.numero) && abs(w.cadre.minY - f.minY) < 6 && w.cadre.milieuX > s.maxX && w.cadre.milieuX < f.minX
        }
    }

    /// Message d'alerte affiché sur la flèche (nil si tout va bien).
    var alerte: String? {
        if flecheCachee { return "La flèche de Valance est sous l'encoche : trop d'icônes visibles. Passez-en en « Masquée » dans Réglages → Icônes." }
        if ordreInvalide { return "Le séparateur de Valance est à droite de la flèche : ⌘-glissez-le à sa gauche pour pouvoir masquer." }
        let n = diagnosticsEncoche.reduce(0) { $0 + $1.sousEncoche.count }
        if n > 0 { return "\(n) icône\(n > 1 ? "s passent" : " passe") sous l'encoche : masquez-en davantage." }
        return nil
    }

    // MARK: - Réglages

    func modifier(_ changement: (inout Reglages) -> Void) {
        let ancien = reglages
        var r = reglages
        changement(&r)
        r = r.normalises()
        guard r != ancien else { return }
        reglages = r
        persistance.enregistrer(r)
        if r.repliAutomatique != ancien.repliAutomatique || r.delaiRepli != ancien.delaiRepli {
            evenement(.configurer(repliAutomatique: r.repliAutomatique, delai: r.delaiRepli))
        }
        if r.sectionToujoursMasquee != ancien.sectionToujoursMasquee {
            barre?.activerToujoursMasque(r.sectionToujoursMasquee)
        }
        if r.raccourci != ancien.raccourci || r.raccourciToutReveler != ancien.raccourciToutReveler {
            appliquerRaccourcis()
        }
        if r.revelerAuSurvol != ancien.revelerAuSurvol { configurerSurvol() }
        if r.afficherDisque != ancien.afficherDisque { afficherDisque(r.afficherDisque) }
        if r.inventaireActive != ancien.inventaireActive {
            if r.inventaireActive { lancerInventairePeriodique() } else { arreterInventaire() }
        }
        if r.modeAffichage == .barre { barreSecondaire.fermer() }
        rafraichirAutorisations()
        appliquerLongueurs()
    }

    /// Liaison SwiftUI vers un réglage. SwiftUI appelle ces fermetures sur le fil principal.
    func liaison<T: Sendable>(_ chemin: WritableKeyPath<Reglages, T> & Sendable) -> Binding<T> {
        Binding(get: { MainActor.assumeIsolated { self.reglages[keyPath: chemin] } },
                set: { v in MainActor.assumeIsolated { self.modifier { $0[keyPath: chemin] = v } } })
    }

    func regle(pour bundle: String) -> RegleApp { reglages.regles[bundle] ?? RegleApp() }

    func definirRegle(_ regle: RegleApp, pour bundle: String) {
        modifier { r in
            if regle.estParDefaut { r.regles[bundle] = nil } else { r.regles[bundle] = regle }
        }
    }

    func basculerOuvertureALaConnexion() {
        OuvertureALaConnexion.basculer()
        ouvertureALaConnexion = OuvertureALaConnexion.active
    }

    private func appliquerRaccourcis() {
        var refuses: [RaccourcisGlobaux.Action] = []
        if !raccourcis.definir(reglages.raccourci, pour: .basculer) { refuses.append(.basculer) }
        if !raccourcis.definir(reglages.raccourciToutReveler, pour: .toutReveler) { refuses.append(.toutReveler) }
        raccourciRefuse = refuses
    }

    /// Suspend les raccourcis pendant leur saisie dans les réglages (sinon la combinaison actuelle déclenche).
    func suspendreRaccourcis(_ suspendre: Bool) {
        if suspendre {
            raccourcis.definir(nil, pour: .basculer)
            raccourcis.definir(nil, pour: .toutReveler)
        } else {
            appliquerRaccourcis()
        }
    }

    func rafraichirAutorisations() {
        accessibiliteAccordee = LecteurAccessibilite.estAutorise
        captureAccordee = Captures.estAutorise
    }

    /// Demande l'Accessibilité, puis la relit chaque seconde pendant 2 min : l'utilisateur coche Valance dans
    /// Réglages Système et la page des icônes se remplit sans autre geste.
    func demanderAccessibilite() {
        _ = LecteurAccessibilite.demanderAutorisation()
        rafraichirAutorisations()
        Task { @MainActor [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.accessibiliteAccordee else { break }
                self.rafraichirAutorisations()
                if self.accessibiliteAccordee { self.actualiserInventaire() }
            }
        }
    }

    func demanderCapture() {
        _ = Captures.demanderAutorisation()
        rafraichirAutorisations()
    }

    func ouvrirReglagesSysteme(_ ancre: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(ancre)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Écrans, encoche, survol

    /// Observateurs de notifications sur la file principale : la fermeture est `@Sendable` et ne touche à
    /// l'acteur principal que par `MainActor.assumeIsolated`, valide puisque la file est `.main`.
    private func observerSysteme() {
        let centre = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        observateurs.append(centre.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ecransChanges() }
        })
        // Réveil : les écrans ont pu changer pendant le sommeil.
        observateurs.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ecransChanges() }
        })
        observateurs.append(ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reglages.inventaireActive else { return }
                self.differer(2) { [weak self] in self?.actualiserInventaire() }
            }
        })
        observateurs.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reglages.inventaireActive else { return }
                self.actualiserInventaire()
            }
        })
    }

    private func ecransChanges() {
        actualiserEcrans()
        appliquerLongueurs()
        reprendreAttente(dans: 3)
    }

    /// Refait les rangements mis en attente, une fois les icônes relues.
    func reprendreAttente(dans delai: Double) {
        // Seulement quand un écran sans encoche est branché : sinon rien n'a changé, inutile de tout révéler.
        guard !enAttente.isEmpty, reglages.inventaireActive, ecrans.contains(where: { $0.largeurGaucheEncoche == nil }) else { return }
        differer(delai) { [weak self] in
            guard let self else { return }
            for (cle, s) in self.enAttente { if let i = self.icones.first(where: { $0.cle == cle }) { self.ranger(i, vers: s) } }
        }
    }

    func actualiserEcrans() {
        ecrans = EcransMac.decrire()
        analyserEncoche()
    }

    /// Icônes à l'écran qui chevauchent une encoche (liste des fenêtres, sans autorisation).
    func analyserEncoche() {
        let exclure = barre?.numerosFenetres ?? []
        let fenetres = FenetresMac.liste(niveau: FenetresMac.niveauBarre).filter { !exclure.contains($0.numero) }.map(\.cadre)
        let h = EcransMac.hauteurPrincipal
        diagnosticsEncoche = ecrans.compactMap {
            Analyse.encoche(ecran: $0, fenetres: fenetres, hauteurEcranPrincipal: h, hauteurParDefaut: EcransMac.hauteurBarreParDefaut)
        }
        let cachee = barre?.cadreFleche.map {
            Rangement.flecheCachee($0, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: EcransMac.hauteurBarreParDefaut)
        } ?? false
        // Seul moyen de le dire à l'utilisateur, puisque la flèche est invisible : ouvrir les réglages (une fois par épisode).
        if cachee && !flecheCachee && rangementEnCours == nil && !Autotest.actif { ouvrirReglages() }
        flecheCachee = cachee
        barre?.mettreAJourFleche(visibilite: visibilite, alerte: alerte)
    }

    func sourisDansBarre() -> Bool {
        let p = NSEvent.mouseLocation
        return Ecrans.estDansBarre(x: Double(p.x), y: Double(p.y), ecrans: ecrans, hauteurParDefaut: EcransMac.hauteurBarreParDefaut)
    }

    /// Survol de la flèche : révèle après un court arrêt. Moniteur global des mouvements de souris (aucune
    /// autorisation : seuls les événements clavier en demandent une).
    private func configurerSurvol() {
        if let m = moniteurSurvol { NSEvent.removeMonitor(m) }
        moniteurSurvol = nil
        guard reglages.revelerAuSurvol else { return }
        moniteurSurvol = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.mouvementSouris()
        }
    }

    private func mouvementSouris() {
        guard let zone = barre?.cadreFlecheCocoa else { return }
        let p = NSEvent.mouseLocation
        let dedans = Double(p.x) >= zone.minX - 2 && Double(p.x) <= zone.maxX + 2 && Double(p.y) >= zone.minY - 2
        guard dedans else { debutSurvol = nil; return }
        if visibilite.estRevelee { evenement(.activite); return }
        if let d = debutSurvol {
            if Date().timeIntervalSince(d) > 0.25 { debutSurvol = nil; evenement(.reveler) }
        } else {
            debutSurvol = Date()
            differer(0.3) { [weak self] in self?.mouvementSouris() }
        }
    }

    // MARK: - Inventaire (Accessibilité)

    private func lancerInventairePeriodique() {
        rafraichirAutorisations()
        tachesFond.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.reglages.inventaireActive else { return }
                self.actualiserInventaire()
                self.surveillerChangements()
                try? await Task.sleep(for: .seconds(30))
            }
        })
    }

    private func arreterInventaire() {
        icones = []
    }

    func actualiserInventaire() {
        rafraichirAutorisations()
        guard reglages.inventaireActive, accessibiliteAccordee, !releveEnCours, let barre else { return }
        // Au lancement, macOS ne donne pas tout de suite la place de nos icônes : sans elle, tout paraîtrait visible.
        guard barre.cadreSeparateur != nil, barre.cadreFleche != nil else {
            differer(1) { [weak self] in self?.actualiserInventaire() }
            return
        }
        releveEnCours = true
        let maintenant = Date()
        let cibles = LecteurAccessibilite.cibles().filter { !disjoncteur.estOuvert($0.cle, maintenant: maintenant) }
        let fenetres = FenetresMac.liste(niveau: FenetresMac.niveauBarre, aLEcranSeulement: false)
        let exclure = barre.numerosFenetres
        Task { @MainActor [weak self] in
            // Fermeture @Sendable : elle tourne sur la file d'Accessibilité, hors de l'acteur principal.
            let releve = await avecEcheance(6, file: fileAccessibilite) { @Sendable in
                LecteurAccessibilite.lire(cibles, budget: 5)
            }
            guard let self else { return }
            self.releveEnCours = false
            guard let releve else {
                Journal.app.error("Relevé d'Accessibilité trop long : abandonné")
                return
            }
            let t = Date()
            for c in releve.lentes { self.disjoncteur.signalerEchec(c, maintenant: t) }
            for c in releve.repondu { self.disjoncteur.signalerSucces(c) }
            self.appsEcartees = self.disjoncteur.appsEcartees(maintenant: t)
            // Positions ramenées sur une même barre : l'Accessibilité situe chaque app sur l'écran de son choix.
            let h = EcransMac.hauteurPrincipal, hb = EcransMac.hauteurBarreParDefaut
            let elements = releve.elements
                .filter { Ecrans.ecranDeLaBarre($0.cadre, ecrans: self.ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: hb) != nil }
                .map { e in var e = e; e.cadre = self.ref(e.cadre); return e }
            let fen = fenetres.map { f in FenetreBarre(numero: f.numero, cadre: self.ref(f.cadre)) }
            self.icones = Appariement.apparier(fenetres: fen, elements: elements, exclure: exclure,
                                               separateur: self.barre?.cadreSeparateur.map(self.ref),
                                               toujoursMasque: self.reglages.sectionToujoursMasquee ? self.barre?.cadreToujoursMasque.map(self.ref) : nil)
            self.dernierReleve = t
        }
    }

    /// Clic relayé depuis la barre secondaire : on révèle, puis on « presse » l'icône par l'Accessibilité si
    /// on sait qui elle est ; sinon l'utilisateur clique lui-même sur l'icône révélée.
    /// 1. Vrai menu (la plupart des apps) : lu par l'Accessibilité et réaffiché sous le panneau, car l'icône cachée
    ///    l'ouvrirait hors de l'écran. 2. Sinon (Electron, fenêtres surgissantes) : on révèle et on clique vraiment sur
    ///    l'icône si elle est à l'écran. 3. Sinon : on ouvre l'app.
    private func activer(_ icone: IconeBarre) {
        guard let e = icone.element, LecteurAccessibilite.estAutorise else {
            evenement(.revelerTemporairement(duree: max(reglages.delaiRepli, 5)))
            return
        }
        let pid = e.pid, rang = e.rang, cle = icone.cle, ou = NSEvent.mouseLocation
        Task { @MainActor [weak self] in
            let menu = await avecEcheance(2, file: fileMenus) { @Sendable in LecteurAccessibilite.lireMenu(pid: pid, rang: rang) } ?? nil
            guard let self else { return }
            if let menu, !menu.isEmpty {
                self.afficherMenu(menu, pid: pid, rang: rang, en: ou)
            } else {
                await self.cliquerVraiment(cle: cle, pid: pid)
            }
        }
    }

    private func afficherMenu(_ entrees: [EntreeMenu], pid: pid_t, rang: Int, en point: NSPoint) {
        let relais = RelaisMenu { chemin in
            Task {
                let ok = await avecEcheance(2, file: fileMenus) { @Sendable in
                    LecteurAccessibilite.choisir(pid: pid, rang: rang, chemin: chemin)
                }
                Journal.app.info("Menu relayé, choix \(chemin, privacy: .public) : \(ok == true ? "fait" : "échec", privacy: .public)")
            }
        }
        let menu = relais.construire(entrees)
        relaisMenu = relais
        menu.popUp(positioning: nil, at: NSPoint(x: point.x - 8, y: point.y - 14), in: nil)
    }

    /// Sur un MacBook seul, l'icône révélée tombe souvent sous l'encoche, à quelques points de la partie visible.
    /// macOS refuse d'y déposer une icône : Valance libère plutôt la place de ses propres icônes (espace disque, flèche),
    /// le temps du clic, ce qui décale vers la droite tout ce qui est à leur gauche. Elles reviennent au clic suivant.
    private func cliquerVraiment(cle: String, pid: pid_t) async {
        evenement(.revelerTemporairement(duree: max(reglages.delaiRepli, 8)))
        try? await Task.sleep(for: .milliseconds(450))
        let h = EcransMac.hauteurPrincipal, hb = EcransMac.hauteurBarreParDefaut
        func atteignable(_ c: Cadre) -> Bool {
            Rangement.estAtteignable(x: c.milieuX, y: c.milieuY, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: hb)
        }
        var lu = await relire(cle)
        if let x = lu?.cadre, !atteignable(x), Rangement.depotSousEncoche(x: x.milieuX, y: x.milieuY, ecrans: ecrans,
                                                                          hauteurEcranPrincipal: h, hauteurParDefaut: hb) != nil {
            liberer(true)
            try? await Task.sleep(for: .milliseconds(350))
            lu = await relire(cle)
        }
        if let x = lu?.cadre, atteignable(x) {
            Deplaceur.cliquer(CGPoint(x: x.milieuX, y: x.milieuY))
            if placeLiberee { rendreAuClicSuivant() }
            return
        }
        liberer(false)
        evenement(.masquer)
        NSRunningApplication(processIdentifier: pid)?.activate()
        Journal.app.info("\(cle, privacy: .public) : icône hors de l'écran, app ouverte à la place")
    }

    @ObservationIgnored private var placeLiberee = false
    @ObservationIgnored private var moniteurRetour: Any?

    private func liberer(_ oui: Bool) {
        guard oui != placeLiberee else { return }
        placeLiberee = oui
        barre?.reduireFleche(oui)
        if reglages.afficherDisque { disque?.visible = !oui }
        if !oui, let m = moniteurRetour { NSEvent.removeMonitor(m); moniteurRetour = nil }
    }

    /// Le menu ou la fenêtre de l'app se ferme au clic suivant : nos icônes reviennent alors (au plus tard 30 s après).
    private func rendreAuClicSuivant() {
        differer(0.5) { [weak self] in
            guard let self, self.placeLiberee, self.moniteurRetour == nil else { return }
            self.moniteurRetour = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.differer(0.3) { [weak self] in self?.liberer(false) } }
            }
        }
        differer(30) { [weak self] in self?.liberer(false) }
    }

    // MARK: - Barre secondaire (Enregistrement de l'écran)

    func basculerBarreSecondaire() {
        if barreSecondaire.estOuverte { barreSecondaire.fermer(); return }
        rafraichirAutorisations()
        guard let barre, let ancre = barre.cadreFlecheCocoa,
              let ref = Ecrans.ecran(contenant: ancre.milieuX, ancre.milieuY, parmi: ecrans) ?? ecrans.first else {
            Journal.app.error("Panneau : flèche introuvable (\(String(describing: self.barre?.cadreFlecheCocoa), privacy: .public))")
            return
        }
        // Le panneau s'ouvre sous la barre de l'écran où est la souris ; la flèche y est à la même distance du bord droit.
        let souris = NSEvent.mouseLocation
        let ecran = Ecrans.ecran(contenant: Double(souris.x), Double(souris.y), parmi: ecrans) ?? ref
        let ancreX = ecran.cadre.maxX - (ref.cadre.maxX - ancre.maxX)
        let echelle = Double(barre.ecranFleche?.backingScaleFactor ?? 2)
        let icones = contenuBarreSecondaire()
        let numeros = captureAccordee ? icones.compactMap { $0.fenetre?.numero } : []
        Task { @MainActor [weak self] in
            let images = numeros.isEmpty ? [] : await Captures.capturer(numeros: numeros, echelle: echelle)
            guard let self else { return }
            var parNumero: [UInt32: ImageCapturee] = [:]
            for i in images { parNumero[i.numero] = i }
            let vignettes: [Vignette] = icones.map { i in
                let capture = i.fenetre.flatMap { parNumero[$0.numero] } ?? self.cacheImages[i.cle]
                if let capture { self.cacheImages[i.cle] = capture }
                // Sans Enregistrement de l'écran : l'icône de l'app propriétaire.
                let image = capture.map { NSImage(cgImage: $0.image, size: $0.taille) }
                    ?? Self.symboleSysteme(i.element)
                    ?? i.element.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
                return Vignette(id: i.cle, nom: i.nom, image: image,
                                taille: capture?.taille ?? CGSize(width: 22, height: 22), icone: i)
            }
            let message = vignettes.isEmpty ? "Aucune icône masquée : choisissez-les dans Réglages → Icônes." : nil
            self.barreSecondaire.afficher(vignettes, message: message, ancreX: ancreX, ecran: ecran)
        }
    }

    /// Icônes de macOS (Centre de contrôle, SystemUIServer) que ScreenCaptureKit ne capture pas : un symbole qui
    /// leur ressemble plutôt que l'icône du Centre de contrôle pour toutes.
    private static func symboleSysteme(_ e: ElementAccessible?) -> NSImage? {
        guard let e, let b = e.bundle, b.hasPrefix("com.apple.") else { return nil }
        let texte = [e.titre, e.identifiant, e.nomApp].compactMap { $0?.lowercased() }.joined(separator: " ")
        let table: [(String, String)] = [
            ("bluetooth", "wave.3.right"), ("airdrop", "dot.radiowaves.left.and.right"), ("wi-fi", "wifi"), ("wi‑fi", "wifi"),
            ("sound", "speaker.wave.2.fill"), ("son", "speaker.wave.2.fill"), ("now playing", "play.circle"),
            ("écoute", "play.circle"), ("user", "person.crop.circle"), ("utilisateur", "person.crop.circle"),
            ("battery", "battery.75percent"), ("batterie", "battery.75percent"), ("focus", "moon.fill"),
            ("concentration", "moon.fill"), ("display", "display"), ("écran", "display"), ("time machine", "clock.arrow.circlepath"),
            ("systemuiserver", "clock.arrow.circlepath"), ("textinput", "keyboard"), ("clavier", "keyboard"),
        ]
        guard let nom = table.first(where: { texte.contains($0.0) })?.1,
              let image = NSImage(systemSymbolName: nom, accessibilityDescription: e.titre) else { return nil }
        return image.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
    }

    /// Clic sur la flèche ou raccourci : masque si c'est révélé ; sinon révèle dans la barre ou dans le panneau du
    /// dessous selon le mode et la place qu'il reste sur l'écran de la souris.
    func basculerSelonPlace() {
        if barreSecondaire.estOuverte { barreSecondaire.fermer(); return }
        if visibilite.estRevelee { evenement(.basculer); return }
        switch reglages.modeAffichage {
        case .barre: evenement(.basculer)
        case .dessous: basculerBarreSecondaire()
        case .auto:
            Task { @MainActor [weak self] in
                guard let self else { return }
                let tient = await self.masqueesTiennentDansLaBarre()
                Journal.app.info("Révélation : \(tient ? "dans la barre" : "panneau", privacy: .public)")
                if tient { self.evenement(.basculer) } else { self.basculerBarreSecondaire() }
            }
        }
    }

    /// Sans Accessibilité on ne connaît ni la largeur des icônes masquées ni celle des menus : on révèle dans la barre.
    private func masqueesTiennentDansLaBarre() async -> Bool {
        guard reglages.inventaireActive, accessibiliteAccordee, let f = barre?.cadreFleche.map(ref) else { return true }
        let h = EcransMac.hauteurPrincipal
        let largeur = icones.filter { $0.section == .masquee }.reduce(0) { $0 + $1.cadre.largeur + 4 }
        guard largeur > 0 else { return true }
        func ecranQuartz(_ c: Cadre) -> EcranDecrit? {
            Ecrans.ecranDeLaBarre(c, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: EcransMac.hauteurBarreParDefaut)
        }
        let souris = NSEvent.mouseLocation
        guard let ici = Ecrans.ecran(contenant: Double(souris.x), Double(souris.y), parmi: ecrans), let ref = ecranQuartz(f) else { return true }
        var largeurMenus = 0.0
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let m = await avecEcheance(0.5, file: fileAccessibilite, { @Sendable in LecteurAccessibilite.finMenus(pid: pid) }) ?? nil,
           let e = ecranQuartz(m) {
            largeurMenus = m.maxX - Repere.versQuartz(e.cadre, hauteurEcranPrincipal: h).minX
        }
        let distance = Repere.versQuartz(ref.cadre, hauteurEcranPrincipal: h).maxX - f.minX
        return Rangement.tientDansLaBarre(largeurIcones: largeur, distanceFlecheBordDroit: distance, largeurMenusApp: largeurMenus, ecran: ici)
    }

    // MARK: - Rangement (V6)

    /// Met l'icône dans la section voulue en la ⌘-glissant. Les demandes s'enchaînent une par une.
    func ranger(_ icone: IconeBarre, vers section: ValanceCoeur.Section) {
        rafraichirAutorisations()
        guard accessibiliteAccordee else { demanderAccessibilite(); return }
        fileRangement.removeAll { $0.cle == icone.cle }
        fileRangement.append((icone.cle, section))
        if rangementEnCours == nil { rangerSuivante() }
    }

    private func rangerSuivante() {
        guard !fileRangement.isEmpty else {
            rangementEnCours = nil
            appliquerLongueurs()
            // Relu une fois les icônes revenues à leur place, sinon elles paraissent toutes visibles.
            differer(0.8) { [weak self] in self?.actualiserInventaire() }
            return
        }
        let (cle, vers) = fileRangement.removeFirst()
        rangementEnCours = cle
        messageRangement = nil
        barreSecondaire.fermer()
        appliquerLongueurs()   // tout à l'écran
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            let erreur = await self.deplacer(cle: cle, vers: vers)
            if erreur == Self.attenteEcran {
                self.enAttente[cle] = vers
                Journal.app.info("Rangement de \(cle, privacy: .public) en attente d'un écran plus large")
            } else if let erreur {
                self.enAttente[cle] = nil
                self.messageRangement = erreur
                Journal.app.error("Rangement de \(cle, privacy: .public) : \(erreur, privacy: .public)")
            }
            if erreur == nil { self.enAttente[cle] = nil }
            self.rangerSuivante()
        }
    }

    /// Deux essais au plus ; renvoie un message d'échec, ou nil si l'icône est dans la bonne section.
    private func deplacer(cle: String, vers: ValanceCoeur.Section) async -> String? {
        let h = EcransMac.hauteurPrincipal, hb = EcransMac.hauteurBarreParDefaut
        for _ in 0..<3 {
            // Tout est ramené sur la barre du plus large écran, et c'est là qu'on glisse.
            guard let barre, let f = barre.cadreFleche.map(ref), let s = barre.cadreSeparateur.map(ref) else { return "icônes de Valance introuvables" }
            let t = reglages.sectionToujoursMasquee ? barre.cadreToujoursMasque.map(ref) : nil
            guard let lu = await relire(cle) else { return "icône introuvable (l'app a-t-elle quitté ?)" }
            let e = ref(lu.cadre)
            if Disposition.section(de: e, separateur: s, toujoursMasque: t) == vers { return nil }
            guard let cible = Rangement.pointDeDepot(vers: vers, fleche: f, separateur: s, toujoursMasque: t) else {
                return "activez la section « toujours masquée » dans Réglages → Sections"
            }
            let depart = (x: e.milieuX, y: e.milieuY)
            var arrivee = cible, sousEncocheAccepte = false
            // MacBook seul : le point visé pour masquer tombe sous l'encoche, où macOS accepte quand même le dépôt.
            if vers != .visible, let d = Rangement.depotSousEncoche(x: cible.x, y: cible.y, ecrans: ecrans, hauteurEcranPrincipal: h,
                                                                   hauteurParDefaut: hb) { arrivee = d; sousEncocheAccepte = true }
            guard Rangement.estAtteignable(x: depart.x, y: depart.y, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: hb),
                  sousEncocheAccepte || Rangement.estAtteignable(x: arrivee.x, y: arrivee.y, ecrans: ecrans, hauteurEcranPrincipal: h, hauteurParDefaut: hb) else {
                return Self.attenteEcran
            }
            await Deplaceur.glisser(de: CGPoint(x: depart.x, y: depart.y), a: CGPoint(x: arrivee.x, y: arrivee.y))
            try? await Task.sleep(for: .milliseconds(500))
        }
        return "l'icône n'a pas bougé (cette app refuse peut-être d'être déplacée)"
    }

    /// Relit par l'Accessibilité l'élément d'une icône (cadre à jour), d'après sa clé.
    private func relire(_ cle: String) async -> ElementAccessible? {
        let cibles = LecteurAccessibilite.cibles().filter { c in icones.contains { $0.cle == cle && $0.element?.pid == c.pid } }
        guard !cibles.isEmpty else { return nil }
        let releve = await avecEcheance(2, file: fileMenus) { @Sendable in LecteurAccessibilite.lire(cibles, budget: 1.5) }
        return releve?.elements.first { IconeBarre(fenetre: nil, element: $0, section: .visible).cle == cle }
    }

    /// Icônes à montrer : celles de l'inventaire (avec les règles) si l'Accessibilité est active, sinon toutes
    /// les fenêtres de barre situées à gauche de notre séparateur.
    private func contenuBarreSecondaire() -> [IconeBarre] {
        if reglages.inventaireActive && !icones.isEmpty {
            return Regles.contenuBarreSecondaire(icones: icones, regles: reglages.regles, inclureToujoursMasquees: false)
        }
        guard let barre, let s = barre.cadreSeparateur else { return [] }
        let exclure = barre.numerosFenetres
        // Chaque barre (un écran = une barre) a sa copie de chaque icône : on ne garde que celle de notre séparateur.
        let fenetres = FenetresMac.liste(niveau: FenetresMac.niveauBarre, aLEcranSeulement: false).filter { abs($0.cadre.minY - s.minY) < 4 }
        return Appariement.apparier(fenetres: fenetres, elements: [], exclure: exclure, separateur: barre.cadreSeparateur,
                                    toujoursMasque: reglages.sectionToujoursMasquee ? barre.cadreToujoursMasque : nil)
            .filter { $0.section == .masquee }
    }

    /// Règle « signaler les changements » : capture ponctuelle des icônes surveillées, comparaison d'empreintes,
    /// révélation brève si l'une a changé.
    private func surveillerChangements() {
        guard reglages.signalerChangements, Captures.estAutorise, !visibilite.estRevelee else { return }
        let surveillees = Regles.surveillees(icones: icones, regles: reglages.regles)
        detecteur.garder(seulement: Set(surveillees.map(\.cle)))
        let numeros = surveillees.compactMap { $0.fenetre?.numero }
        guard !numeros.isEmpty else { return }
        let cles = Dictionary(surveillees.compactMap { i in i.fenetre.map { ($0.numero, i.cle) } }, uniquingKeysWith: { a, _ in a })
        Task { @MainActor [weak self] in
            let images = await Captures.capturer(numeros: numeros, echelle: 1)
            guard let self else { return }
            var change = false
            let t = Date()
            for img in images {
                guard let cle = cles[img.numero], let gris = Captures.niveauxDeGris(img.image), let e = Empreinte(gris) else { continue }
                if self.detecteur.observer(cle: cle, empreinte: e, maintenant: t) { change = true }
            }
            if change { self.evenement(.revelerTemporairement(duree: self.reglages.dureeSignalement)) }
        }
    }

    // MARK: - Menu et fenêtres

    private func construireMenu() -> NSMenu {
        let menu = NSMenu()
        let racc = reglages.raccourci.map { "  (\($0.description))" } ?? ""
        menu.addItem(ItemAction((visibilite.estRevelee ? "Masquer les icônes" : "Révéler les icônes") + racc) { [weak self] in
            self?.evenement(.basculer)
        })
        menu.addItem(ItemAction(visibilite == .toutRevele ? "Tout masquer" : "Tout révéler (⌥-clic)") { [weak self] in
            self?.evenement(.basculerTout)
        })
        menu.addItem(ItemAction("Montrer en dessous") { [weak self] in self?.basculerBarreSecondaire() })
        if let a = alerte {
            menu.addItem(.separator())
            let item = NSMenuItem(title: a, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ItemAction("Réglages…", touche: ",") { [weak self] in self?.ouvrirReglages() })
        menu.addItem(ItemAction("Rechercher des mises à jour…") { NSApp.activate(); miseAJour.checkForUpdates(nil) })
        menu.addItem(ItemAction("Ouvrir à la connexion", coche: ouvertureALaConnexion) { [weak self] in
            self?.basculerOuvertureALaConnexion()
        })
        menu.addItem(.separator())
        menu.addItem(ItemAction("Quitter Valance", touche: "q") { NSApp.terminate(nil) })
        return menu
    }

    func ouvrirReglages() {
        if fenetreReglages == nil {
            let hote = NSHostingController(rootView: VueReglages(controleur: self))
            let f = NSWindow(contentViewController: hote)
            f.title = "Réglages de Valance"
            f.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            f.setContentSize(NSSize(width: 760, height: 520))
            f.isReleasedWhenClosed = false
            f.center()
            f.setFrameAutosaveName("valance.reglages")
            fenetreReglages = f
        }
        rafraichirAutorisations()
        NSApp.activate()
        fenetreReglages?.makeKeyAndOrderFront(nil)
    }

    var fenetreReglagesOuverte: Bool { fenetreReglages?.isVisible ?? false }

    func fermerReglages() { fenetreReglages?.close() }

    // MARK: - Outils

    /// Cadre de barre ramené sur la barre du plus large écran (voir `Ecrans.versReference`).
    private func ref(_ c: Cadre) -> Cadre {
        Ecrans.versReference(c, ecrans: ecrans, hauteurEcranPrincipal: EcransMac.hauteurPrincipal,
                             hauteurParDefaut: EcransMac.hauteurBarreParDefaut)
    }

    private func differer(_ secondes: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(secondes * 1000)))
            action()
        }
    }
}

/// Menu de Valance qui reproduit celui d'une icône cachée ; un choix est rejoué dans le vrai menu.
@MainActor
final class RelaisMenu: NSObject {
    private let rejouer: ([Int]) -> Void

    init(rejouer: @escaping ([Int]) -> Void) { self.rejouer = rejouer }

    func construire(_ entrees: [EntreeMenu], chemin: [Int] = []) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, e) in entrees.enumerated() {
            if e.separateur { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: e.titre, action: e.enfants.isEmpty ? #selector(choisi(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.isEnabled = e.actif
            item.state = e.coche ? .on : .off
            item.representedObject = chemin + [i]
            if !e.enfants.isEmpty { item.submenu = construire(e.enfants, chemin: chemin + [i]) }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func choisi(_ item: NSMenuItem) {
        if let chemin = item.representedObject as? [Int] { rejouer(chemin) }
    }
}
