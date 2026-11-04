# Valance

Gestionnaire de la barre des menus de macOS 26 : masque les icônes encombrantes derrière un séparateur, les révèle d'un clic
sur la flèche ou d'un raccourci, les replie seul.
Affiche aussi la place libre du disque. Gratuit, licence MIT. Aucune autorisation pour l'essentiel, aucune télémétrie ; seul accès réseau : la recherche de mises à jour (Sparkle, depuis les Releases de ce dépôt).

## Installer

Téléchargez `Valance-<version>.dmg` dans les [Releases](https://github.com/AnthonyTrtre/valance/releases/latest), glissez
Valance dans Applications. L'app n'est pas notarisée : au premier lancement, clic droit → Ouvrir (ou Réglages Système →
Confidentialité et sécurité → Ouvrir quand même). Les versions suivantes s'installent seules.

## Développer

- `docs/decisions.md` : choix techniques. `ValanceKit/` : la logique pure (paquet SwiftPM, testée aussi sous Linux).
  `Sources/` : la coque d'app AppKit + SwiftUI. `Socle/` : briques communes (journal, barre des menus).

```
make test-kit     # logique pure (aussi sous Linux : cd ValanceKit && swift test)
make test         # + tests de l'app (Xcode)
make autotest     # parcours automatique de la CI, en local
make installer    # compile en Release et installe dans /Applications
Scripts/publier.sh 0.3.0   # DMG + zip Sparkle + appcast, à joindre à la Release v0.3.0
```

## Prise en main

 lancez Valance, ouvrez Réglages → **Icônes**, accordez l'Accessibilité, puis choisissez la section de
chaque icône (Visible, Masquée) : Valance la ⌘-glisse lui-même à sa place. On peut aussi ⌘-glisser à la main : ce qui est à
gauche de la flèche ‹ est masqué, ce qui est à sa droite reste visible. Clic sur la flèche : révéler / masquer ; ⌥-clic : tout révéler ;
clic droit : menu ; ⌃⌥⌘V : raccourci global.
