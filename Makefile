# make projet | build | test | test-kit | lancer | installer | autotest | tcc-reset
# Les produits de compilation vont hors iCloud (D008).
DD := $(HOME)/Developer/builds/valance
XB := xcodebuild -project Valance.xcodeproj -scheme Valance -derivedDataPath $(DD)
APP := $(DD)/Build/Products/Release/Valance.app

projet: ; xcodegen generate
build: projet ; $(XB) -configuration Release build
test: projet test-kit ; $(XB) test
# Logique pure (géométrie, séparateur, encoche, machine à états, règles…) : aussi sous Linux.
test-kit: ; cd ValanceKit && swift test --scratch-path $(DD)/kit
lancer: build ; open "$(APP)"
installer: build ; ditto "$(APP)" "/Applications/Valance.app" && open "/Applications/Valance.app"
# Parcours automatique de la CI, en local (réglages en mémoire, rien n'est enregistré).
autotest: build ; VALANCE_AUTOTEST=1 "$(APP)/Contents/MacOS/Valance"
# Débogage seulement : oublie les autorisations Accessibilité et Enregistrement de l'écran de Valance.
tcc-reset: ; tccutil reset Accessibility fr.anthony.valance; tccutil reset ScreenCapture fr.anthony.valance
