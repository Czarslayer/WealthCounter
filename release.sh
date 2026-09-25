#!/bin/zsh
# Builds the app and packages it as WealthCounter.dmg with a custom drag-to-Applications window.
set -e
cd "$(dirname "$0")"

./build.sh

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcrun swift Icon/make_dmg_background.swift .build

# dmgbuild writes the Finder layout directly, no Finder scripting needed.
if [[ ! -x .build/venv/bin/dmgbuild ]]; then
    python3 -m venv .build/venv
    .build/venv/bin/pip install -q dmgbuild
fi

DMG=WealthCounter.dmg
rm -f "$DMG"
.build/venv/bin/dmgbuild -s Icon/dmg_settings.py -D app=/Applications/RealTimeCounter.app "WealthCounter" "$DMG"
echo "✅ Created $DMG"
