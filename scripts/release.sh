#!/usr/bin/env bash
set -euo pipefail

# MagicQuit release script — run on a machine with signing credentials (see RELEASING.md):
#   - Developer ID Application certificate in the keychain
#   - notarytool credentials: an App Store Connect API key at
#     ~/.appstoreconnect/clavus-notary.json (+ private_keys/AuthKey_<id>.p8),
#     else the `magicquit-notary` keychain profile — see "Notary credentials" below
#   - Sparkle's generate_appcast on PATH (and the EdDSA private key in the keychain)
#   - gh CLI authenticated (for the GitHub release)

cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project MagicQuit.xcodeproj -scheme MagicQuit -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/ {print $3; exit}')
ARCHIVE=build/release/MagicQuit.xcarchive
EXPORT_DIR=build/release/export
RELEASES_DIR=build/release/releases
ZIP="MagicQuit-$VERSION.zip"

echo "==> Releasing MagicQuit $VERSION"

# Notary credentials — resolved and PROVEN here, before the multi-minute
# archive, so a bad credential costs seconds instead of a whole build.
#
# The App Store Connect API key wins when present because it is a FILE.
# notarytool keeps keychain profiles in the data-protection keychain, which
# only a process in an interactive GUI session can read: a release driven from
# a script or agent context fails with "No Keychain password item found" even
# though the profile is present and works from Terminal (verified 2026-07-29,
# see clavus-server/AGENTS.md). The key also authenticates without the Apple
# ID, so a locked account cannot block a release. MagicQuit is on the same
# team as Clavus (4HMNGH59W8), so it uses the same key.
ASC_CONFIG="$HOME/.appstoreconnect/clavus-notary.json"
if [[ -f "$ASC_CONFIG" ]]; then
    KEY_FILE="$HOME/.appstoreconnect/private_keys/$(plutil -extract keyFile raw -o - "$ASC_CONFIG")"
    [[ -f "$KEY_FILE" ]] || { echo "API key file missing: $KEY_FILE" >&2; exit 1; }
    NOTARY_ARGS=(--key "$KEY_FILE"
                 --key-id "$(plutil -extract keyId raw -o - "$ASC_CONFIG")"
                 --issuer "$(plutil -extract issuerId raw -o - "$ASC_CONFIG")")
    echo "==> Notary auth: App Store Connect API key"
else
    NOTARY_ARGS=(--keychain-profile magicquit-notary)
    echo "==> Notary auth: keychain profile magicquit-notary"
fi
if ! xcrun notarytool history "${NOTARY_ARGS[@]}" --no-progress >/dev/null 2>&1; then
    echo "Notary credentials unusable. Either create the API key (preferred, cannot vanish):" >&2
    echo "  $ASC_CONFIG + ~/.appstoreconnect/private_keys/AuthKey_<id>.p8" >&2
    echo "  (App Store Connect -> Users and Access -> Integrations)" >&2
    echo "or re-create the keychain profile FROM A TERMINAL WINDOW:" >&2
    echo "  xcrun notarytool store-credentials magicquit-notary \\" >&2
    echo "    --apple-id <apple-id> --team-id 4HMNGH59W8 --password <app-specific-password>" >&2
    exit 1
fi

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
xcrun notarytool submit "$RELEASES_DIR/$ZIP" "${NOTARY_ARGS[@]}" --wait
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
