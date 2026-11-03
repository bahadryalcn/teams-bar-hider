#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app="$project_root/dist/macos/Teams Bar Hider.app"
mkdir -p "$app/Contents/MacOS"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
MACOSX_DEPLOYMENT_TARGET=12.0 swiftc -O -sdk "$sdk" "$project_root/macos/TeamsBarHider.swift" -o "$app/Contents/MacOS/TeamsBarHider" -framework AppKit -framework ApplicationServices
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.teamsbarhider.app</string>
<key>CFBundleName</key><string>Teams Bar Hider</string>
<key>CFBundleDisplayName</key><string>Teams Bar Hider</string>
<key>CFBundleExecutable</key><string>TeamsBarHider</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>0.5.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSAccessibilityUsageDescription</key><string>Hide only the Microsoft Teams screen-sharing toolbar and restore it on request.</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.teamsbarhider.app "$app"
"$app/Contents/MacOS/TeamsBarHider" --self-test
codesign --verify --strict "$app"
cp "$project_root/macos/Install.command" "$project_root/macos/Uninstall.command" "$project_root/dist/macos/"
cp "$project_root/README.md" "$project_root/LICENSE" "$project_root/THIRD-PARTY-NOTICES.md" "$project_root/dist/macos/"
chmod +x "$project_root/dist/macos/Install.command" "$project_root/dist/macos/Uninstall.command"
echo "Built $app"
