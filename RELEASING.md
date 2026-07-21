# Releasing MagicQuit

One-time setup on the release machine, then a single script per release.

## One-time setup

1. **Developer ID certificate** — make sure a "Developer ID Application" certificate for team `4HMNGH59W8` is in the keychain (Xcode → Settings → Accounts → Manage Certificates).

2. **Notarization credentials** — create an app-specific password on appleid.apple.com, then:
   ```bash
   xcrun notarytool store-credentials magicquit-notary \
     --apple-id <apple-id> --team-id 4HMNGH59W8 --password <app-specific-password>
   ```

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
