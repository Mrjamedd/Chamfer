#!/bin/bash
# Assembles Chamfer.app from a release build.
#
# SwiftPM produces a bare executable. macOS needs a bundle for almost
# everything that makes an app an app: a version somebody can read, a Dock
# icon, security-scoped bookmarks, notarisation — and Sparkle, which stores the
# update feed and its public key in Info.plist and does nothing without them.
#
#   Scripts/package.sh 1.2.0 41
#
# Version and build number come from the caller, because the release workflow
# derives them from the tag and a local run should not have to invent them.
# Signing and notarisation are deliberately NOT here: this script produces the
# same bundle on a developer's Mac and in CI, and only CI has the identity.
set -euo pipefail

VERSION="${1:-0.0.0}"
BUILD="${2:-0}"
FEED_URL="${SPARKLE_FEED_URL:-}"
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/artifacts/Chamfer.app"
CONTENTS="$APP/Contents"

echo "==> Building Chamfer $VERSION ($BUILD)"
swift build -c release --product Chamfer

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

cp "$ROOT/.build/release/Chamfer" "$CONTENTS/MacOS/Chamfer"

# Sparkle ships as an XCFramework. The slice for this architecture has to live
# inside the bundle, and the executable has to be able to find it at runtime —
# hence the rpath below. Without both, the app launches and dies on first use.
SPARKLE_FRAMEWORK="$(find "$ROOT/.build" -maxdepth 6 -name "Sparkle.framework" -path "*macos*" -print -quit || true)"
if [ -n "$SPARKLE_FRAMEWORK" ]; then
  echo "==> Embedding $(basename "$(dirname "$SPARKLE_FRAMEWORK")")/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK" "$CONTENTS/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$CONTENTS/MacOS/Chamfer" 2>/dev/null || true
else
  echo "!!! Sparkle.framework not found — the bundle will not be able to update itself"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Chamfer</string>
  <key>CFBundleDisplayName</key><string>Chamfer</string>
  <key>CFBundleIdentifier</key><string>com.chamfer.app</string>
  <key>CFBundleExecutable</key><string>Chamfer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <!-- Chamfer has a window and belongs in the Dock while it is open. -->
  <key>LSUIElement</key><false/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Chamfer</string>
  <!-- The folder picker is how a vault is connected, and the only reason
       Chamfer ever asks for access to anything. -->
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Chamfer reads and tidies the Markdown notes in folders you connect.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Chamfer reads and tidies the Markdown notes in folders you connect.</string>
$(if [ -n "$FEED_URL" ]; then cat <<FEED
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <!-- Once a day. An updater that checks on every launch is a network request
       somebody did not ask for, several times a morning. -->
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
FEED
fi)
</dict>
</plist>
PLIST

if [ -f "$ROOT/Resources/Chamfer.icns" ]; then
  cp "$ROOT/Resources/Chamfer.icns" "$CONTENTS/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Chamfer" \
    "$CONTENTS/Info.plist" >/dev/null
fi

echo "==> $APP"
if [ -z "$FEED_URL" ]; then
  echo "    (no update feed: this bundle will not check for updates)"
fi
