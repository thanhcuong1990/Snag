#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/mac/Snag.xcodeproj}"
SCHEME="${SCHEME:-Snag}"
CONFIGURATION="${CONFIGURATION:-Release}"
INFO_PLIST="${INFO_PLIST:-$ROOT_DIR/mac/Snag/Info.plist}"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
TAG="${TAG:-v$VERSION}"
APP_NAME="${APP_NAME:-Snag}"
DMG_BASENAME="${DMG_BASENAME:-${APP_NAME}_${VERSION}}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/.build/DerivedData-mac}"
STAGE_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGE_DIR"
}

trap cleanup EXIT

mkdir -p "$OUT_DIR"
rm -rf "$DERIVED_DATA"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  find "$DERIVED_DATA/Build/Products" -maxdepth 3 -name "*.app" -print >&2 || true
  exit 1
fi

cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

DMG_PATH="$OUT_DIR/$DMG_BASENAME.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

if [[ "${UPLOAD:-1}" == "0" ]]; then
  echo "$DMG_PATH"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install it and run: gh auth login" >&2
  echo "$DMG_PATH" >&2
  exit 1
fi

RELEASE_TITLE="${RELEASE_TITLE:-$TAG}"
NOTES="${NOTES:-}"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG_PATH" --clobber
else
  gh release create "$TAG" "$DMG_PATH" --title "$RELEASE_TITLE" --notes "$NOTES"
fi

echo "$DMG_PATH"

