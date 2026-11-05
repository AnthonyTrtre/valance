# Décisions propres à Valance

## V1 — Masquer par séparateur extensible, sans API privée
Un `NSStatusItem` élargi à (largeur du plus grand écran + 200 pt, entre 1 000 et 10 000 pt) pousse hors de l'écran tout ce qui
est à sa gauche. Public, sans autorisation, marche sous Tahoe. Positions mémorisées par AppKit via des `autosaveName` définitifs.
Garde-fou : on ne masque pas si le séparateur est à droite de la flèche (la flèche partirait hors de l'écran).

## V2 — Raccourci par Carbon plutôt que KeyboardShortcuts
`RegisterEventHotKey` suffit, est public et ne demande aucune autorisation ; pas de dépendance tierce à épingler.
Le rappel C est une fonction globale non isolée qui repasse par une tâche `@MainActor` (leçon de Slipway).

## V3 — Accessibilité isolée et bornée
Lecture `AXExtrasMenuBar` app par app sur une file dédiée, 0,25 s par message, 5 s au total, échéance de 6 s côté appelant
(`avecEcheance`), disjoncteur (2 échecs → app ignorée 5 min). Le fil principal n'attend jamais une app gelée.
Pas de service XPC pour l'instant : la file + l'échéance protègent l'interface ; un XPC protégerait aussi d'un plantage
d'AX, à envisager si cela arrive.

## V4 — Pas de ⌘-glisser simulé (remplacée par V6 le 2026-11-04)
Valance ne déplace pas les icônes des autres apps : il dit lesquelles ⌘-glisser, et où (conseils issus des règles). C'est la
partie qui a le plus souffert chez Bartender 6 sous macOS 26 (curseur détourné, clics fantômes).

## V5 — Captures ponctuelles, autorisation à la demande
La barre secondaire capture chaque fenêtre d'icône (`SCScreenshotManager`, filtre « fenêtre indépendante ») à l'ouverture
du panneau, jamais en flux. L'Enregistrement de l'écran n'est demandé que quand l'utilisateur active la fonction.
La CI lance l'app 10 s et un parcours automatique (`VALANCE_AUTOTEST=1`) pour attraper les violations d'isolation Swift 6.

## V6 — Valance range lui-même les icônes (remplace V4)
Besoin : choisir les icônes dans les réglages. Un changement de section dans Réglages → Icônes ⌘-glisse l'icône
(`CGEvent`, Accessibilité) juste à droite de la flèche ou juste à gauche d'un séparateur, barre tout révélée, puis remet le
curseur et vérifie (deux nouveaux essais au plus). Jamais en tâche de fond. Positions ramenées sur la barre du plus large
écran avant toute comparaison (l'Accessibilité situe chaque app sur l'écran de son choix) ; on glisse sur cette barre-là.

## V7 — Écran à encoche seul : dépôt sous l'encoche, flèche cachée signalée
Sur un MacBook sans autre écran, le point visé pour masquer (juste à gauche du séparateur) tombe souvent sous l'encoche.
macOS y accepte pourtant le dépôt : on vise alors le milieu de l'encoche (jamais à droite du point d'origine), loin du
séparateur, car un dépôt tout contre lui fait sauter l'icône voisine de l'autre côté. Ramener une icône en Visible reste
impossible depuis l'encoche (on ne peut pas la saisir). Si la flèche passe sous l'encoche (trop d'icônes visibles), elle
est invisible : Valance ouvre ses réglages avec un avertissement, une fois par épisode. Un cadre de fenêtre vide (hauteur 0,
donné par macOS au lancement) vaut « position inconnue », sinon l'ordre paraissait faux et le masquage restait suspendu.

## V8 — Une icône, une seule fois, même sur plusieurs écrans (0.3.2)

Sous macOS 26, chaque barre (une par écran) a sa propre fenêtre pour chaque icône, nos fenêtres comprises. Une fenêtre
sans élément d'Accessibilité qui recouvre une icône déjà retenue, ou l'une de nos fenêtres, est une copie : on l'écarte.
Sinon le panneau montrait des doublons sans nom, et la largeur des icônes masquées (copies du séparateur comprises)
envoyait dans le panneau ce qui tenait dans la barre. Deux cadres désignent la même icône quand leur IoU dépasse 0,5 ou
que l'un est presque entier dans l'autre (la fenêtre d'une icône système fait deux fois la largeur de son élément).
Les captures du panneau se font en parallèle ; les icônes de macOS que ScreenCaptureKit ne capture pas reçoivent un
symbole SF qui leur ressemble.

## V9 — La flèche est la frontière (0.3.2)

Le trait du séparateur ne s'affiche plus (seulement pendant un rangement). On ⌘-glisse directement dans la barre : à gauche
de la flèche, masquée ; à droite, visible. Une icône posée entre le séparateur (invisible, collé à la flèche) et la flèche
est ⌘-glissée par Valance à gauche du séparateur au moment de masquer, comme Réglages → Icônes. Recréer le séparateur à une
position écrite à la main ne marche pas pendant que l'app tourne (AppKit efface la position au retrait). La révélation
dans la barre reste jusqu'au clic suivant ; le panneau du dessous (quand les icônes ne tiennent pas, MacBook seul) se
ferme seul dès que la souris quitte le panneau et la barre juste au-dessus.

## V10 — Trois zones dans la barre (0.3.3)

La section « toujours masquée » est active par défaut. Son séparateur porte un repère, un œil barré collé à son bord droit
(une vue, car un bouton de barre centre son image), visible même quand il est élargi : à droite de la flèche, toujours
visible ; entre l'œil et la flèche, visible au clic ; à gauche de l'œil, caché sauf au ⌥-clic.

## V11 — Réglages qu'on change et rechange (0.3.4)

- Sous macOS 26, retirer une icône (`removeStatusItem`) ou la cacher (`isVisible = false`) fait oublier sa place à AppKit :
  rallumée, elle revient n'importe où (l'espace disque dans la zone masquée, l'œil barré à droite des icônes masquées).
  Éteindre l'espace disque ou la section « toujours cachée » met donc l'icône à une largeur nulle, à sa place.
- Le premier relevé attend que macOS donne la place de nos icônes, et le relevé qui suit un rangement attend que les
  icônes soient revenues : sinon tout paraissait « visible » quelques secondes.
- MacBook seul : une icône sous l'encoche ne peut pas être saisie. Le choix est retenu (« en attente ») et appliqué dès
  qu'un écran sans encoche est branché, au lieu d'un message d'erreur.
- Réglages → Icônes : « Visible / Au clic / Cachée », l'horloge et le Centre de contrôle (inamovibles) n'y figurent plus,
  la liste technique des apps qui ne répondent pas non plus.

## V12 — Cliquer une icône du panneau ouvre vraiment son menu (0.3.5)

Une icône masquée ouvre son menu là où elle est, donc hors de l'écran. Valance lit le menu par l'Accessibilité
(`AXExtrasMenuBar` → `AXMenu`), le referme (`AXCancel`) et le réaffiche lui-même sous le panneau ; un choix est rejoué dans
le vrai menu. Ces appels ont leur propre file : derrière un relevé de plusieurs secondes, ils échouaient. Les apps qui
ne répondent qu'à un vrai clic (Electron : Plaud ; fenêtres surgissantes) sont révélées puis cliquées ; si l'icône
tombe sous l'encoche, Valance réduit à rien sa flèche et l'espace disque le temps du clic (ils reviennent au clic
suivant), car macOS refuse d'y déposer une autre icône. Sinon, l'app elle-même est ouverte.

## V13 — Barre ou panneau : un choix stable (0.3.6)

Le choix dépend de la largeur des icônes masquées, tirée du dernier relevé. Ce relevé se faisait aussi 0,4 s après une
révélation : sur un écran étroit, les icônes qui débordent ont alors des positions fausses et passaient pour visibles
(13 masquées, puis 1, puis 13 ; 42 pt puis 4 026 pt). Plus de relevé pendant une révélation, sauf celui qui suit un
rangement ; il est refait après le masquage. La lecture des menus de l'app au premier plan a sa file, comme les menus.

## V14 — Pourcentage restant de Claude dans la barre (0.4.0)

L'app Claude garde sa connexion pour elle, et lire un jeton à la main (trousseau, puis `api/oauth/usage`) obligerait à
le renouveler, au risque de déconnecter Claude Code. Valance lance donc Claude Code en mode SDK (`claude -p
--input-format stream-json`), envoie `initialize` puis `get_usage` et lit `rate_limits.seven_day.utilization` : aucun
message au modèle, aucun jeton manipulé, Claude Code gère sa connexion. Toutes les 10 minutes, et à l'ouverture du menu si
le relevé a plus de 2 minutes. `get_usage` est marquée expérimentale par Claude Code : si elle change, l'icône affiche
« — » avec la raison dans son menu. Option désactivée par défaut ; Claude Code doit être connecté (`claude auth login`).

## V15 — Panneau au niveau de la barre, quel que soit l'écran actif (0.4.1)

`isFloatingPanel = true` remet le niveau du panneau à « flottant » (3) : réglé avant, `.statusBar` était perdu, et sur un
écran inactif le panneau passait sous la barre ou ne s'affichait pas. Le niveau est maintenant réglé après. À savoir : sur
un écran inactif, macOS garde le premier clic dans la barre pour activer cet écran ; seul le second atteint la flèche.

## V16 — Changer l'ordre depuis une bande glissable (0.4.2)

En tête de Réglages → Icônes, une bande reproduit la barre : les icônes s'écartent en direct pendant le glisser, et ce
n'est qu'au lâcher que Valance ⌘-glisse l'icône contre le bord de sa voisine (zone comprise de part et d'autre des repères).
Vers la droite, macOS 26 ignore un ⌘-glisser simulé rapide : ce sens-là dure ~1,5 s ; vers la gauche, il reste rapide. Une
icône masquée lue hors de l'écran juste après la révélation est relue au lieu de conclure à un écran trop étroit.

