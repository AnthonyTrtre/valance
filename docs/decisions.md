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
