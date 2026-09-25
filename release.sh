#!/bin/zsh
# Builds the app and packages it as WealthCounter.dmg (drag-to-Applications installer).
set -e
cd "$(dirname "$0")"

./build.sh

STAGING=.build/dmg
DMG=WealthCounter.dmg
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R /Applications/RealTimeCounter.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "WealthCounter" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "✅ Created $DMG"
