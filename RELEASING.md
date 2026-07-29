# Releasing MagicQuit

One-time setup on the release machine, then a single script per release.

## One-time setup

1. **Developer ID certificate** — make sure a "Developer ID Application" certificate for team `4HMNGH59W8` is in the keychain (Xcode → Settings → Accounts → Manage Certificates).

2. **Notarization credentials** — use an **App Store Connect API key**, not an app-specific password. Create one under App Store Connect → Users and Access → Integrations → Team Keys, then place both files:
   ```
   ~/.appstoreconnect/clavus-notary.json
     {"keyId": "<10 chars>", "issuerId": "<uuid>", "keyFile": "AuthKey_<keyId>.p8"}
   ~/.appstoreconnect/private_keys/AuthKey_<keyId>.p8      (chmod 600)
   ```
   MagicQuit shares team `4HMNGH59W8` with Clavus, so one key covers both — if you already set this up for clavus-server/clavus-desktop, there is nothing to do here.

   The older `xcrun notarytool store-credentials magicquit-notary --apple-id … --password <app-specific-password>` form still works and `release.sh` falls back to it, but prefer the key: notarytool writes keychain profiles into the **data-protection keychain**, which only a process in an interactive GUI session can read. A release run from a script, CI job or coding agent then fails with `No Keychain password item found` even though the profile is present and works from a Terminal window — and `security dump-keychain | grep notary` will *also* say it is missing, which is a false negative. Verified 2026-07-29; details in `clavus-server/AGENTS.md`. If you do use a profile, create it from a real Terminal window, and test it with `xcrun notarytool history --keychain-profile magicquit-notary` rather than any `security` command. A key file has none of these failure modes and does not involve the Apple ID at all.

3. **Sparkle tools + EdDSA keys** — install the Sparkle distribution tools and generate the update-signing keys **once**:
   ```bash
   brew install --cask sparkle   # provides generate_keys / generate_appcast / sign_update
   generate_keys                  # stores the private key in the keychain, prints the public key
   ```
   Paste the printed public key into `MagicQuit/Info.plist` as the value of `SUPublicEDKey` (currently a placeholder), commit, and never regenerate these keys — shipped apps only accept updates signed with this exact key. Keep a backup: `generate_keys -x sparkle-private-key-backup.pem` (store it in a password manager, NOT in the repo).

4. **gh CLI** — `gh auth login` (used to create the GitHub release).

## Per release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project, update `CHANGELOG.md`, commit.
2. Run:
   ```bash
   ./scripts/release.sh
   ```
   This archives, exports with Developer ID, notarizes + staples, zips, regenerates `appcast.xml`, prints the zip's SHA256, and creates the GitHub release.
3. Commit + push the updated `appcast.xml` (the app checks `https://raw.githubusercontent.com/BigBerny/magicquit/main/appcast.xml`).
4. Homebrew: update `packaging/homebrew/magicquit.rb` (version + sha256). For the official repo, submit with:
   ```bash
   brew bump-cask-pr magicquit --version 2.0
   ```
   (First-time submission instead: PR the cask file to homebrew/homebrew-cask.)

## Notes

- Sparkle runs fully silent (`SUAutomaticallyUpdate`): users get updates in the background, no dialogs. The updater only starts when `SUPublicEDKey` is set to a real key, so development builds never phone home.
- The app is not sandboxed, so no Sparkle XPC services are needed.
