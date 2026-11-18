#!/bin/bash
# Packages an unsigned `flutter build ios --no-codesign` into an IPA for
# sideloading (AltStore, SideStore, Sideloadly, LiveContainer).
#
# Each bundle is ad hoc signed with its entitlements, inside out (frameworks,
# then extensions, then the app), so the sideloader can read them, re-sign
# with the user's Apple ID and remap the App Group the widget shares with the
# app. No Apple Developer account is needed. Same approach as BitChord-iOS's
# scripts/make-ipa.sh.
#
#   scripts/ios/make_ipa.sh [path/to/Runner.app] [output.ipa]
set -euo pipefail
cd "$(dirname "$0")/../.."

APP=${1:-build/ios/iphoneos/Runner.app}
[ -d "$APP" ] || { echo "no app at $APP (run flutter build ios --release --no-codesign first)" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist")
OUT=${2:-build/ios/Inzx-$VERSION-$BUILD.ipa}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/Inzx.app"
STAGED="$STAGE/Payload/Inzx.app"

find "$STAGED" -name "*.framework" -type d -prune | while read -r fw; do
  codesign --force --sign - --timestamp=none "$fw"
done
find "$STAGED" -name "*.dylib" -type f | while read -r lib; do
  codesign --force --sign - --timestamp=none "$lib"
done
if [ -d "$STAGED/PlugIns" ]; then
  for appex in "$STAGED"/PlugIns/*.appex; do
    [ -d "$appex" ] || continue
    name=$(basename "$appex" .appex)
    ent="ios/$name/$name.entitlements"
    if [ -f "$ent" ]; then
      codesign --force --sign - --timestamp=none --entitlements "$ent" "$appex"
    else
      codesign --force --sign - --timestamp=none "$appex"
    fi
  done
fi
codesign --force --sign - --timestamp=none --entitlements ios/Runner/Runner.entitlements "$STAGED"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(cd "$STAGE" && zip -qry - Payload) > "$OUT"
echo "$OUT"
