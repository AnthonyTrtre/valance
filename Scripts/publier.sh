#!/bin/zsh
# Fabrique une version publiable de Valance : build Release signé, archive de mise à jour Sparkle
# (Valance-<version>.zip, signée EdDSA), appcast.xml et DMG, à joindre à la Release GitHub v<version>.
# Les apps installées lisent releases/latest/download/appcast.xml et se mettent à jour seules.
# La clé EdDSA reste dans le Trousseau (compte « utahpik-valance ») ; elle n'est jamais affichée.
#
# Usage : Scripts/publier.sh <version>       ex. Scripts/publier.sh 0.2.0
#         puis : gh release create v<version> ~/Developer/builds/valance-publication/{*.dmg,*.zip,appcast.xml,SHA256SUMS.txt}
set -euo pipefail
cd "${0:A:h}/.."

VERSION=${1:?usage : publier.sh <version>}
SORTIE="$HOME/Developer/builds/valance-publication"
DD="$SORTIE/derived"
APP="$DD/Build/Products/Release/Valance.app"
rm -rf "$SORTIE"; mkdir -p "$SORTIE"

xcodegen generate --quiet
# Numéro de build croissant (date) : Sparkle compare CFBundleVersion.
xcodebuild -project Valance.xcodeproj -scheme Valance -configuration Release -derivedDataPath "$DD" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" -quiet build
codesign --verify --deep --strict "$APP"

SPARKLE="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"
MAJ="$SORTIE/maj"; mkdir -p "$MAJ"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$MAJ/Valance-$VERSION.zip"
"$SPARKLE/generate_appcast" --account utahpik-valance \
  --download-url-prefix "https://github.com/AnthonyTrtre/valance/releases/download/v$VERSION/" \
  --link "https://github.com/AnthonyTrtre/valance" --maximum-versions 1 "$MAJ"
mv "$MAJ/Valance-$VERSION.zip" "$MAJ/appcast.xml" "$SORTIE/"; rm -rf "$MAJ"

PREPA="$SORTIE/dmg"; mkdir -p "$PREPA"
ditto "$APP" "$PREPA/Valance.app"
ln -s /Applications "$PREPA/Applications"
# hdiutil produit parfois une image corrompue (constaté sous macOS 26.6) : vérifiée, refaite au besoin.
for essai in 1 2 3 4 5; do
  rm -f "$SORTIE/Valance-$VERSION.dmg"
  hdiutil create -quiet -volname "Valance $VERSION" -srcfolder "$PREPA" -fs HFS+ -format UDZO "$SORTIE/Valance-$VERSION.dmg"
  hdiutil verify -quiet "$SORTIE/Valance-$VERSION.dmg" 2>/dev/null && break
  echo "DMG corrompu (essai $essai), nouvel essai"
  (( essai == 5 )) && { echo "DMG toujours corrompu"; exit 1; }
done
rm -rf "$PREPA" "$DD"
( cd "$SORTIE" && shasum -a 256 "Valance-$VERSION.dmg" "Valance-$VERSION.zip" | tee SHA256SUMS.txt )
echo "Prêt : $SORTIE (DMG, zip Sparkle, appcast.xml, SHA256SUMS.txt)"
