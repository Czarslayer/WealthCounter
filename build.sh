#!/bin/zsh
# Builds RealTimeCounter.app (menu bar only, no Dock icon) and copies it to /Applications.
set -e
cd "$(dirname "$0")"

# Use Xcode's toolchain (the custom swift.org toolchain fails signing the manifest).
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcrun swift build -c release

APP=".build/RealTimeCounter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RealTimeCounter "$APP/Contents/MacOS/"

# Re-render the icon when the SVG changed.
if [[ ! -f Icon/AppIcon.icns || Icon/AppIcon.svg -nt Icon/AppIcon.icns ]]; then
    xcrun swift Icon/make_icon.swift
    iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
    rm -rf Icon/AppIcon.iconset
fi
cp Icon/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RealTime Counter</string>
    <key>CFBundleIdentifier</key><string>com.czar.RealTimeCounter</string>
    <key>CFBundleExecutable</key><string>RealTimeCounter</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

INSTALLED="/Applications/RealTimeCounter.app"
pkill -x RealTimeCounter || true
rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"
rm -rf "$APP"   # keep a single copy so Spotlight/Launchpad don't list it twice
open "$INSTALLED"
echo "✅ Installed and launched $INSTALLED"
