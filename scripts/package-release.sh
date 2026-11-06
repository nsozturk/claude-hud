#!/usr/bin/env bash
# Build every download for a GitHub release into build/release/:
#   Claude-HUD-<v>.dmg                 universal (Apple Silicon + Intel), drag to Applications
#   Claude-HUD-<v>-universal.zip       same app as a zip
#   Claude-HUD-<v>-arm64.zip           Apple Silicon only
#   Claude-HUD-<v>-x86_64.zip          Intel only
#   SHA256SUMS.txt                     checksums of all of the above
#   claude-hud.rb                      Homebrew cask for the DMG (put it in a tap)
# SIGN_IDENTITY="Developer ID Application: …" signs for distribution; default is ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Packaging/Info.plist)
OUT="build/release"
rm -rf "$OUT" build/arch build/stage-*                 # only this script's own output
mkdir -p "$OUT" build/arch

SOURCES=$(ls */*.swift | grep -v '^Tests/')
for arch in arm64 x86_64; do
  echo "→ Compiling $arch"
  swiftc -O -parse-as-library -target "$arch-apple-macos14.0" -o "build/arch/ClaudeHUD-$arch" $SOURCES
done
lipo -create -output build/arch/ClaudeHUD-universal build/arch/ClaudeHUD-arm64 build/arch/ClaudeHUD-x86_64

make_app() {  # $1 = binary, $2 = folder that receives "Claude HUD.app"
  local app="$2/Claude HUD.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$1" "$app/Contents/MacOS/ClaudeHUD"
  cp Packaging/Info.plist "$app/Contents/Info.plist"
  cp bin/claude-hud-hook "$app/Contents/Resources/claude-hud-hook"
  chmod +x "$app/Contents/Resources/claude-hud-hook"
  if ! xcrun actool Packaging/AppIcon.icon --compile "$app/Contents/Resources" --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist "build/icon-partial.plist" >/dev/null 2>&1; then
    cp Packaging/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
  fi
  codesign --force --deep -s "${SIGN_IDENTITY:--}" "$app"
}

for variant in universal arm64 x86_64; do
  echo "→ Packaging $variant"
  make_app "build/arch/ClaudeHUD-$variant" "build/stage-$variant"
  ditto -c -k --keepParent "build/stage-$variant/Claude HUD.app" "$OUT/Claude-HUD-$VERSION-$variant.zip"
done

echo "→ DMG"
# Branded window (background + icon layout) via dmgbuild, installed once into build/.
DMGBUILD="build/dmgbuild-venv/bin/dmgbuild"
if [ ! -x "$DMGBUILD" ]; then
  python3 -m venv build/dmgbuild-venv && build/dmgbuild-venv/bin/pip -q install dmgbuild
fi
"$DMGBUILD" -s Packaging/dmg/settings.py \
  -D app="build/stage-universal/Claude HUD.app" \
  -D background=Packaging/dmg/background.tiff \
  "Claude HUD $VERSION" "$OUT/Claude-HUD-$VERSION.dmg"

DMG_SHA=$(shasum -a 256 "$OUT/Claude-HUD-$VERSION.dmg" | cut -d' ' -f1)
cat > "$OUT/claude-hud.rb" <<CASK
cask "claude-hud" do
  version "$VERSION"
  sha256 "$DMG_SHA"

  url "https://github.com/nsozturk/claude-hud/releases/download/v#{version}/Claude-HUD-#{version}.dmg"
  name "Claude HUD"
  desc "Answer Claude Code questions and permission prompts from the MacBook notch"
  homepage "https://github.com/nsozturk/claude-hud"

  depends_on macos: ">= :sonoma"

  app "Claude HUD.app"

  zap trash: "~/Library/Preferences/dev.lamma.ClaudeHUD.plist"
end
CASK

(cd "$OUT" && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt)
echo "✓ Release files in $OUT:"
ls -lh "$OUT"
