#!/usr/bin/env bash
set -euo pipefail

# MagicQuit release script — run on a machine with signing credentials (see RELEASING.md):
#   - Developer ID Application certificate in the keychain
#   - notarytool credentials stored as:  xcrun notarytool store-credentials magicquit-notary
#   - Sparkle's generate_appcast on PATH (and the EdDSA private key in the keychain)
#   - gh CLI authenticated (for the GitHub release)

cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project MagicQuit.xcodeproj -scheme MagicQuit -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/ {print $3; exit}')
ARCHIVE=build/release/MagicQuit.xcarchive
EXPORT_DIR=build/release/export
RELEASES_DIR=build/release/releases
ZIP="MagicQuit-$VERSION.zip"

echo "==> Releasing MagicQuit $VERSION"

rm -rf build/release
mkdir -p "$RELEASES_DIR"

echo "==> Archiving"
xcodebuild -project MagicQuit.xcodeproj -scheme MagicQuit -configuration Release \
    -archivePath "$ARCHIVE" archive

echo "==> Exporting with Developer ID signing"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/MagicQuit.app"

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$RELEASES_DIR/$ZIP"
xcrun notarytool submit "$RELEASES_DIR/$ZIP" --keychain-profile magicquit-notary --wait
xcrun stapler staple "$APP"

echo "==> Zipping stapled app"
rm "$RELEASES_DIR/$ZIP"
ditto -c -k --keepParent "$APP" "$RELEASES_DIR/$ZIP"

echo "==> Generating appcast"
generate_appcast "$RELEASES_DIR" \
    --download-url-prefix "https://github.com/BigBerny/magicquit/releases/download/v$VERSION/"
cp "$RELEASES_DIR/appcast.xml" appcast.xml

echo "==> SHA256 for the Homebrew cask"
shasum -a 256 "$RELEASES_DIR/$ZIP"

echo "==> Creating GitHub release v$VERSION"
gh release create "v$VERSION" "$RELEASES_DIR/$ZIP" --title "MagicQuit $VERSION" --generate-notes \
    --target "$(git rev-parse HEAD)"

echo
echo "Done. Still to do:"
echo "  - commit + push the updated appcast.xml"
echo "  - update packaging/homebrew/magicquit.rb (version + sha256) and bump the cask"
