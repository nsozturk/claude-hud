#!/usr/bin/env bash
# Build "build/Claude HUD.app" from source with the Swift toolchain (no Xcode project needed).
#   SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh   # sign with your certificate
#   ./scripts/build-app.sh                                        # ad-hoc signature
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Claude HUD.app"
echo "→ Building $APP"
rm -rf "$APP"                                  # only this script's own output
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Every source except the test target.
SOURCES=$(ls */*.swift | grep -v '^Tests/' | grep -v '^build/')
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/ClaudeHUD" $SOURCES

cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp bin/claude-hud-hook "$APP/Contents/Resources/claude-hud-hook"
chmod +x "$APP/Contents/Resources/claude-hud-hook"

# App icon: macOS 26+ wants an Icon Composer icon (Assets.car); actool from Xcode 26 builds it.
# Older toolchains fall back to the classic .icns, which macOS 26 may show on a gray plate.
if xcrun actool Packaging/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
     --minimum-deployment-target 14.0 --app-icon AppIcon \
     --output-partial-info-plist build/icon-partial.plist >/dev/null 2>&1; then
  echo "→ Icon: Icon Composer (Assets.car)"
else
  cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  echo "→ Icon: classic .icns (install Xcode 26+ for the new icon format)"
fi

codesign --force --deep -s "${SIGN_IDENTITY:--}" "$APP"
echo "✓ Built $APP"
echo "  Install: cp -R \"$APP\" /Applications/ && open \"/Applications/Claude HUD.app\""
