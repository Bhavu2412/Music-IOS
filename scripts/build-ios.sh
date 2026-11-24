#!/usr/bin/env bash
# Builds Music.ipa for iPhone. Same signing modes as the `of` repo's
# macos-dev-up.sh `ios` stage, so local runs and CI behave the same:
#
#   (no env)                          → output/ios/Music-unsigned.ipa
#                                       Not installable as-is; proves the device build and can be re-signed.
#   DEVELOPMENT_TEAM=<id>             → output/ios/Music.ipa, automatic signing. Works with a free
#                                       Personal Team: needs that Apple ID in Xcode → Settings → Accounts
#                                       and the iPhone connected once so Xcode registers it.
#
#   BUNDLE_ID_PREFIX=com.you          → com.you.Music, com.you.Music.Widgets, group.com.you.Music
#                                       (default: the value in project.yml).
#   CONFIGURATION=Debug|Release       → default Release.
#
# Development-signed .ipas install on devices registered in the team's profile
# (Xcode → Devices, Apple Configurator, or `xcrun devicectl device install app`).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT_DIR="$ROOT/output/ios"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Music.xcarchive"
# Only override project.yml's prefix when asked to.
PREFIX="${BUNDLE_ID_PREFIX:-$(awk '/^ *BUNDLE_ID_PREFIX:/ {print $2; exit}' project.yml)}"
PREFIX_ARGS=()
[ -n "${BUNDLE_ID_PREFIX:-}" ] && PREFIX_ARGS=("BUNDLE_ID_PREFIX=$BUNDLE_ID_PREFIX")
CONFIGURATION="${CONFIGURATION:-Release}"

log()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || die "xcodebuild not found. Install Xcode, then: sudo xcode-select --switch /Applications/Xcode.app"
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || die "xcodegen not found (brew install xcodegen)"
  log "Installing xcodegen…"
  brew install xcodegen >/dev/null
fi

log "Xcode:  $(xcodebuild -version | head -n1)"
log "Bundle: $PREFIX.Music ($CONFIGURATION)"
xcodegen generate --quiet

# Unsigned unless DEVELOPMENT_TEAM is given; command-line settings beat project.yml.
SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
PROVISIONING_ARGS=()
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
  log "Signing with team $DEVELOPMENT_TEAM (automatic)"
  SIGNING_ARGS=(CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
    CODE_SIGN_STYLE=Automatic "CODE_SIGN_IDENTITY=Apple Development")
  # Distinct flag, not a build setting: lets xcodebuild register App IDs and mint
  # profiles through the Apple ID signed into Xcode the first time.
  PROVISIONING_ARGS=(-allowProvisioningUpdates)
fi

rm -rf "$BUILD_DIR"
mkdir -p "$OUT_DIR"

log "Archiving Music…"
xcodebuild archive \
  -project Music.xcodeproj \
  -scheme Music \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -quiet \
  ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} \
  ${PREFIX_ARGS[@]+"${PREFIX_ARGS[@]}"} \
  "${SIGNING_ARGS[@]}"
[ -d "$ARCHIVE" ] || die "Archive step finished but produced no $ARCHIVE"

if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
  log "Exporting a signed .ipa…"
  cat > "$BUILD_DIR/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>debugging</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    -quiet \
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
  cp "$BUILD_DIR/export/Music.ipa" "$OUT_DIR/Music.ipa"
  log "Done: $OUT_DIR/Music.ipa"
else
  # No team, so -exportArchive would fail. An .ipa is a zip with the .app under
  # Payload/: enough to inspect or re-sign later.
  warn "DEVELOPMENT_TEAM not set: packaging an UNSIGNED .ipa (not installable on a device as-is)."
  mkdir -p "$BUILD_DIR/Payload"
  cp -R "$ARCHIVE/Products/Applications/Music.app" "$BUILD_DIR/Payload/"
  # zip adds to an existing archive, so start fresh to avoid stale files.
  rm -f "$OUT_DIR/Music-unsigned.ipa"
  (cd "$BUILD_DIR" && zip -qry "$OUT_DIR/Music-unsigned.ipa" Payload)
  log "Done: $OUT_DIR/Music-unsigned.ipa"
fi
