<p align="center">
  <img src="MagicQuit/Assets.xcassets/Image.imageset/256.png" width="128" alt="MagicQuit icon">
</p>

<h1 align="center">MagicQuit</h1>

<p align="center">Automatically quits apps you are no longer using.<br>Lives in the menu bar, stays out of your way.</p>

---

MagicQuit keeps your Mac tidy without you noticing it. Two mechanisms, both optional per app:

- **Idle quit** — apps you haven't used for a while (default: 8 hours) are quit automatically. One setting, fixed steps from 15 minutes to 48 hours.
- **Quit on last window close** — when you close an app's last window, the app quits, like on Windows. Close the last Preview window, Preview is gone.

Everything is exclude-based: both features apply to all regular apps, and you maintain a short list of exceptions. Media players (Music, Spotify, Podcasts, VLC) are excluded from window-close quitting by default so your audio keeps playing.

## Install

Download the latest release from the [Releases page](https://github.com/BigBerny/magicquit/releases), unzip, and drag `MagicQuit.app` into `/Applications`.

<!-- Once the cask is published:
```
brew install --cask magicquit
```
-->

Requires macOS 14 or later.

## Usage

- Click the menu bar icon to see all running apps with their remaining time.
- The checkbox next to each app enables/disables idle quitting for it — unchecked apps are never touched.
- The ↩ button resets an app's timer.
- Settings: idle duration, launch at login, quit-on-last-window-close with its exclusion list.

### Accessibility permission

The window-close feature uses the Accessibility API to count an app's windows (it is the only reliable way to also see minimized windows). macOS will ask you to grant access in **System Settings → Privacy & Security → Accessibility** the first time you enable the feature. The idle-quit feature needs no permissions.

## How it quits apps

MagicQuit always quits apps politely (the equivalent of ⌘Q). Apps with unsaved changes will ask you to save instead of losing data; MagicQuit never force-kills anything.

## Building

Open `MagicQuit.xcodeproj` in Xcode 16 or later and build the `MagicQuit` scheme. Unit tests: `xcodebuild test -scheme MagicQuit`.

## License

[MIT](LICENSE)
