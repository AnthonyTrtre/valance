import AppKit
import SwiftUI
import ValanceCoeur

/// Rubriques de la barre latérale des réglages.
enum Rubrique: String, CaseIterable, Identifiable {
    case general, raccourcis, sections, ecrans, inventaire, barreSecondaire, apropos

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .general: "Général"
        case .raccourcis: "Raccourcis"
        case .sections: "Sections"
        case .ecrans: "Écrans et encoche"
        case .inventaire: "Icônes"
        case .barreSecondaire: "Affichage"
        case .apropos: "À propos"
        }
    }

    var symbole: String {
        switch self {
        case .general: "gearshape"
        case .raccourcis: "keyboard"
        case .sections: "rectangle.split.3x1"
        case .ecrans: "display.2"
        case .inventaire: "list.bullet.rectangle"
        case .barreSecondaire: "menubar.dock.rectangle"
        case .apropos: "info.circle"
        }
    }
}

struct VueReglages: View {
    let controleur: Controleur
    @State private var rubrique: Rubrique? = .general

    var body: some View {
        NavigationSplitView {
            List(Rubrique.allCases, selection: $rubrique) { r in
                Label(r.titre, systemImage: r.symbole).tag(r)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch rubrique ?? .general {
                case .general: VueGeneral(controleur: controleur)
                case .raccourcis: VueRaccourcis(controleur: controleur)
                case .sections: VueSections(controleur: controleur)
                case .ecrans: VueEcrans(controleur: controleur)
                case .inventaire: VueInventaire(controleur: controleur)
                case .barreSecondaire: VueOptionBarreSecondaire(controleur: controleur)
                case .apropos: VueAPropos()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((rubrique ?? .general).titre)
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear { controleur.rafraichirAutorisations() }
    }
}

// MARK: - Général

struct VueGeneral: View {
    let controleur: Controleur

    var body: some View {
        Form {
            Section {
                Text("Valance masque les icônes placées à gauche de son séparateur (le trait fin à côté de la flèche). "
                     + "Choisissez lesquelles dans Réglages → Icônes, ou ⌘-glissez-les vous-même de part et d'autre du séparateur.")
                    .foregroundStyle(.secondary)
                if controleur.ordreInvalide {
                    Label("Le séparateur est à droite de la flèche : ⌘-glissez-le à sa gauche, sinon Valance ne peut pas masquer.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("Repli") {
                Toggle("Replier automatiquement", isOn: controleur.liaison(\.repliAutomatique))
                LabeledContent("Délai") {
                    HStack {
                        Slider(value: controleur.liaison(\.delaiRepli), in: 2...120, step: 1)
                            .frame(maxWidth: 240)
                        Text("\(Int(controleur.reglages.delaiRepli)) s").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!controleur.reglages.repliAutomatique)
                Text("Le repli attend que la souris quitte la barre et qu'aucun menu ne soit ouvert.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Comportement") {
                Toggle("Révéler au survol de la flèche", isOn: controleur.liaison(\.revelerAuSurvol))
                Toggle("Afficher le séparateur quand les icônes sont révélées", isOn: controleur.liaison(\.afficherSeparateur))
                Toggle("Retrouver le même état après un redémarrage", isOn: controleur.liaison(\.memoriserEtat))
            }
            Section("Espace disque") {
                Toggle("Afficher la place libre du disque dans la barre", isOn: controleur.liaison(\.afficherDisque))
                Text("Même chiffre que le Finder (espace récupérable compris), relu chaque minute ; orange sous 10 % ou 20 Go. "
                     + "Cliquez dessus pour voir tous les disques.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Démarrage") {
                Toggle("Ouvrir Valance à la connexion", isOn: Binding(
                    get: { MainActor.assumeIsolated { controleur.ouvertureALaConnexion } },
                    set: { v in MainActor.assumeIsolated { if v != controleur.ouvertureALaConnexion { controleur.basculerOuvertureALaConnexion() } } }))
                if !Bundle.main.bundlePath.hasPrefix("/Applications/") {
                    Text("Fiable seulement pour la copie installée dans /Applications (`make installer`).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Raccourcis

struct VueRaccourcis: View {
    let controleur: Controleur

    var body: some View {
        Form {
            Section {
                LabeledContent("Révéler ou masquer") {
                    EnregistreurRaccourci(controleur: controleur, valeur: controleur.liaison(\.raccourci))
                }
                if controleur.raccourciRefuse.contains(.basculer) {
                    Text("Ce raccourci est déjà pris par une autre app : choisissez-en un autre.")
                        .font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Tout révéler") {
                    EnregistreurRaccourci(controleur: controleur, valeur: controleur.liaison(\.raccourciToutReveler))
                }
                if controleur.raccourciRefuse.contains(.toutReveler) {
                    Text("Ce raccourci est déjà pris par une autre app.").font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Raccourcis globaux du système (API Carbon) : aucune autorisation demandée. "
                     + "Il faut au moins ⌃, ⌥ ou ⌘ (ou une touche de fonction seule). ⎋ annule la saisie, ⌫ efface.")
            }
            Section("Souris") {
                LabeledContent("Clic sur la flèche", value: controleur.reglages.modeAffichage.libelle)
                LabeledContent("⌥-clic", value: "tout révéler (section toujours masquée comprise)")
                LabeledContent("Clic droit ou ⌃-clic", value: "menu")
            }
        }
    }
}

/// Saisie d'un raccourci : un clic, puis la combinaison. Moniteur clavier **local** (notre fenêtre seulement) :
/// pas d'autorisation.
struct EnregistreurRaccourci: View {
    let controleur: Controleur
    @Binding var valeur: Raccourci?
    @State private var enSaisie = false
    @State private var moniteur: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                enSaisie ? arreter() : commencer()
            } label: {
                Text(enSaisie ? "Tapez la combinaison…" : (valeur?.description ?? "Aucun"))
                    .frame(minWidth: 140)
            }
            if valeur != nil && !enSaisie {
                Button {
                    valeur = nil
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .help("Effacer")
            }
        }
        .onDisappear { arreter() }
    }

    private func commencer() {
        enSaisie = true
        controleur.suspendreRaccourcis(true)
        moniteur = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
            if e.keyCode == 0x35 { arreter(); return nil }                         // ⎋
            if e.keyCode == 0x33 && e.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                valeur = nil; arreter(); return nil                                // ⌫
            }
            let mods = Modificateurs(drapeauxCocoa: e.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            let r = Raccourci(codeTouche: e.keyCode, modificateurs: mods, libelle: e.charactersIgnoringModifiers)
            guard r.estValide else { NSSound.beep(); return nil }
            valeur = r
            arreter()
            return nil
        }
    }

    private func arreter() {
        if let m = moniteur { NSEvent.removeMonitor(m) }
        moniteur = nil
        if enSaisie { controleur.suspendreRaccourcis(false) }
        enSaisie = false
    }
}

// MARK: - Sections

struct VueSections: View {
    let controleur: Controleur

    var body: some View {
        Form {
            Section {
                Toggle("Section « toujours masquée »", isOn: controleur.liaison(\.sectionToujoursMasquee))
            } footer: {
                Text("Ajoute un second séparateur, à gauche du premier. Les icônes à sa gauche restent cachées même "
                     + "quand on révèle la barre ; ⌥-clic sur la flèche (ou le second raccourci) montre tout.")
            }
            Section("Disposition") {
                Text("visible  ‹ flèche ›  |  masquée  |  toujours masquée")
                    .font(.system(.body, design: .monospaced))
                Text("Les positions sont mémorisées par macOS. Quittez Bartender ou tout autre gestionnaire de barre : "
                     + "deux gestionnaires se disputent les positions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Écrans

struct VueEcrans: View {
    let controleur: Controleur

    var body: some View {
        Form {
            Section("Écrans") {
                ForEach(controleur.ecrans) { e in
                    LabeledContent(e.nom) {
                        VStack(alignment: .trailing) {
                            Text("\(Int(e.cadre.largeur)) × \(Int(e.cadre.hauteur)) pt · barre \(Int(e.hauteurBarre)) pt")
                            Text(e.aUneEncoche ? "encoche : \(Int(e.encoche(hauteurParDefaut: 24)?.largeur ?? 0)) pt de large" : "sans encoche")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Longueur du séparateur masquant",
                               value: "\(Int(LongueurSeparateur.pourMasquer(largeursEcrans: controleur.ecrans.map(\.cadre.largeur)))) pt")
            }
            Section("Encoche") {
                if controleur.diagnosticsEncoche.isEmpty {
                    Text("Aucun écran à encoche.").foregroundStyle(.secondary)
                }
                ForEach(controleur.diagnosticsEncoche, id: \.ecran) { d in
                    if d.aDesIconesCachees {
                        Label("\(d.sousEncoche.count) icône(s) passent derrière l'encoche : macOS ne les replie pas. "
                              + "⌘-glissez-en quelques-unes à gauche du séparateur.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Aucune icône sous l'encoche.", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                }
                Button("Analyser maintenant") { controleur.actualiserEcrans() }
                Text("L'analyse lit la position des icônes à l'écran (sans autorisation). Faites-la barre révélée pour vérifier le pire cas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Inventaire et règles

struct VueInventaire: View {
    let controleur: Controleur

    var body: some View {
        Form {
            Section {
                Toggle("Identifier et ranger les icônes (Accessibilité)", isOn: Binding(
                    get: { MainActor.assumeIsolated { controleur.reglages.inventaireActive } },
                    set: { v in MainActor.assumeIsolated {
                        controleur.modifier { $0.inventaireActive = v }
                        if v && !controleur.accessibiliteAccordee { controleur.demanderAccessibilite() }
                    } }))
                if controleur.reglages.inventaireActive && !controleur.accessibiliteAccordee {
                    HStack {
                        Label("Autorisation Accessibilité non accordée.", systemImage: "lock")
                        Spacer()
                        Button("Ouvrir les Réglages Système") { controleur.ouvrirReglagesSysteme("Privacy_Accessibility") }
                    }
                }
            } footer: {
                Text("Choisissez la section de chaque icône : Valance la ⌘-glisse lui-même à sa place (le curseur bouge un "
                     + "instant, puis revient). macOS retient ensuite cette place. L'Accessibilité sert à savoir quelle icône est "
                     + "laquelle et à la déplacer.")
            }
            if controleur.reglages.inventaireActive && controleur.accessibiliteAccordee {
                Section {
                    HStack {
                        Button(controleur.releveEnCours ? "Lecture…" : "Actualiser") { controleur.actualiserInventaire() }
                            .disabled(controleur.releveEnCours || controleur.rangementEnCours != nil)
                        if controleur.rangementEnCours != nil {
                            ProgressView().controlSize(.small)
                            Text("Rangement… ne touchez pas la souris").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let d = controleur.dernierReleve {
                            Text("Relevé à \(d.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let m = controleur.messageRangement {
                        Label("Rangement impossible : \(m).", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    if !controleur.appsEcartees.isEmpty {
                        Text("Apps qui ne répondent pas (ignorées 5 min) : \(controleur.appsEcartees.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                ForEach(sections, id: \.self) { section in
                    let liste = controleur.icones.filter { $0.section == section && $0.element != nil }
                    Section("\(section.libelle) (\(liste.count))") {
                        ForEach(liste) { i in LigneIcone(controleur: controleur, icone: i, sections: sections) }
                    }
                }
            }
        }
    }

    private var sections: [ValanceCoeur.Section] {
        controleur.reglages.sectionToujoursMasquee ? ValanceCoeur.Section.allCases : [.visible, .masquee]
    }
}

struct LigneIcone: View {
    let controleur: Controleur
    let icone: IconeBarre
    let sections: [ValanceCoeur.Section]

    var body: some View {
        HStack {
            if let pid = icone.element?.pid, let image = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: image).resizable().frame(width: 18, height: 18)
            }
            Text(icone.nom)
            if controleur.rangementEnCours == icone.cle { ProgressView().controlSize(.small) }
            Spacer()
            Picker("", selection: Binding(
                get: { icone.section },
                set: { s in MainActor.assumeIsolated { controleur.ranger(icone, vers: s) } })) {
                ForEach(sections, id: \.self) { Text($0.libelle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: sections.count == 3 ? 330 : 200)
            if let bundle = icone.element?.bundle {
                Toggle("Signaler", isOn: Binding(
                    get: { MainActor.assumeIsolated { controleur.regle(pour: bundle).signalerChangements } },
                    set: { v in MainActor.assumeIsolated {
                        var r = controleur.regle(pour: bundle); r.signalerChangements = v; controleur.definirRegle(r, pour: bundle)
                    } }))
                    .toggleStyle(.checkbox)
                    .help("Révéler brièvement la barre quand l'image de cette icône change")
                    .disabled(!controleur.reglages.signalerChangements)
            }
        }
    }
}

// MARK: - Barre secondaire

struct VueOptionBarreSecondaire: View {
    let controleur: Controleur

    var body: some View {
        Form {
            Section {
                Picker("Icônes masquées", selection: controleur.liaison(\.modeAffichage)) {
                    ForEach(ModeAffichage.allCases, id: \.self) { Text($0.libelle).tag($0) }
                }
                if !controleur.captureAccordee {
                    HStack {
                        Label("Enregistrement de l'écran non accordé.", systemImage: "lock")
                        Spacer()
                        Button("Demander") { controleur.demanderCapture() }
                        Button("Réglages Système") { controleur.ouvrirReglagesSysteme("Privacy_ScreenCapture") }
                    }
                    Text("Facultatif : sans cette autorisation, le panneau montre l'icône de chaque app au lieu de l'image exacte. "
                         + "Après l'autorisation, macOS demande souvent de relancer Valance.").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("« S'il y a la place » compte, sur l'écran où est la souris, l'espace entre les menus de l'app et la flèche "
                     + "(encoche comprise). Sinon un panneau sous la barre montre les icônes masquées ; un clic sur l'une d'elles "
                     + "l'ouvre. Il faut l'Accessibilité (Réglages → Icônes) pour mesurer la place ; sans elle, on révèle dans la barre.")
            }
            Section {
                Toggle("Révéler brièvement quand une icône surveillée change", isOn: controleur.liaison(\.signalerChangements))
                LabeledContent("Durée") {
                    HStack {
                        Slider(value: controleur.liaison(\.dureeSignalement), in: Reglages.dureeSignalementBornes, step: 1)
                            .frame(maxWidth: 200)
                        Text("\(Int(controleur.reglages.dureeSignalement)) s").monospacedDigit()
                    }
                }
                .disabled(!controleur.reglages.signalerChangements)
            } header: {
                Text("Règle d'affichage")
            } footer: {
                Text("Exige l'Accessibilité (pour savoir quelle icône est laquelle) et l'Enregistrement de l'écran. Une capture "
                     + "toutes les 30 s des seules icônes cochées « Signaler » dans « Icônes ».")
            }
        }
    }
}

// MARK: - À propos

struct VueAPropos: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                LabeledContent("Identifiant", value: Bundle.main.bundleIdentifier ?? "?")
                Text("Gestionnaire de barre des menus pour macOS 26. Aucune télémétrie. Seul accès réseau : la recherche "
                     + "de mises à jour sur GitHub (toutes les 6 h). Logiciel libre, licence MIT.")
                    .foregroundStyle(.secondary)
                Button("Rechercher des mises à jour…") { NSApp.activate(); miseAJour.checkForUpdates(nil) }
            }
            Section("Autorisations") {
                LabeledContent("Masquer, révéler, raccourci, repli", value: "aucune")
                LabeledContent("Identifier les icônes", value: "Accessibilité (si activé)")
                LabeledContent("Barre secondaire, signalement", value: "Enregistrement de l'écran (si activé)")
            }
        }
    }
}
