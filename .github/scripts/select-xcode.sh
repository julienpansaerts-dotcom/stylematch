#!/usr/bin/env bash
# Sélectionne la version de Xcode 26 (ou plus récente) la plus haute installée
# sur le runner. Apple exige Xcode 26 / SDK iOS 26 pour tout envoi sur
# App Store Connect depuis le 28 avril 2026.
set -euo pipefail

candidates=$(ls -d /Applications/Xcode_*.app 2>/dev/null \
  | grep -E 'Xcode_[0-9]+(\.[0-9]+)*\.app$' \
  | sed -E 's#.*/Xcode_([0-9.]+)\.app#\1#' \
  | awk -F. '$1 >= 26' \
  | sort -V)

if [ -z "$candidates" ]; then
  echo "::error::Aucun Xcode 26+ trouvé sur ce runner. Versions disponibles :"
  ls -d /Applications/Xcode*.app || true
  exit 1
fi

version=$(echo "$candidates" | tail -1)
sudo xcode-select -s "/Applications/Xcode_${version}.app/Contents/Developer"
xcodebuild -version
