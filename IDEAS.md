# MagicQuit — Verbesserungsideen (Stand 2026-07-20)

> **STATUS 2026-07-20: Runde 1 UMGESETZT** (Commits b8d433a…996c405, alle auf main gepusht).
> Punkte 1–4 komplett, Punkt 5 vorbereitet, Punkt 7 teilweise. Verbleibende manuelle Schritte (MacBook):
> 1. `generate_keys` ausführen, Public Key in Info.plist `SUPublicEDKey` eintragen (siehe RELEASING.md)
> 2. `./scripts/release.sh` für Release 2.0 (Developer-ID-Signing + Notarization)
> 3. Homebrew-Cask einreichen (packaging/homebrew/magicquit.rb, SHA eintragen)
> 4. On-Device-Verify: Window-Close-Feature mit AX-Berechtigung in echter Session testen
> 5. Offene PRs #16–#19 beantworten/schliessen (durch 2.0 überholt; GitHub-Antworten bewusst Janis überlassen)

Arbeitsliste für die Modernisierungs-Runde. Quellen: eigener Code-Review, GitHub-Issues/PRs (343 ⭐, 19 Issues/PRs), SwiftQuit-Vergleich.

## 1. Neues Feature: Quit beim Schliessen des letzten Fensters (Windows-Verhalten)

- **Kern:** Wenn das letzte Fenster einer App geschlossen wird (z. B. Vorschau), wird die App beendet.
- **Vorarbeit existiert:** PR #18 (@johnyoonh) implementiert genau das via Accessibility API + 1s-Delay-Check. SwiftQuit macht es mit Swindler/AXSwift und konfigurierbarem Close-Delay (Default 2 s).
- **Technische Entscheidung:** Accessibility API (AXIsProcessTrusted) braucht eine Berechtigung, sieht aber auch minimierte Fenster. CGWindowList braucht keine Berechtigung, sieht aber minimierte Fenster NICHT → würde Apps mit minimierten Fenstern fälschlich beenden. → AX API nehmen, Onboarding für die Berechtigung sauber machen.
- **Schutzmechanismen:** Delay vor dem Quit (2–3 s, erneuter Fenster-Check), keine Apps mit unsaved changes hart beenden (`terminate()` ist ohnehin graceful), Apps die gerade Audio abspielen evtl. ausnehmen.
- **Listen:** Nur **Exclude-Liste** (Feature gilt für alle Apps, Ausnahmen definierbar) — einfacher als Include+Exclude. Sinnvolle Default-Excludes vorbefüllen (Musik, Spotify, Mail, Messenger, IDEs?).

## 2. Listen-Konzept vereinheitlichen (beide Features)

- Heute: impliziter Include-Ansatz — jede neue App ist automatisch "quit = an" (`toggleStatus[...] ?? true`). PR #19 will das Default auf "aus" drehen — Gegenposition diskutieren.
- **Vorschlag:** Beide Features (Idle-Quit + Window-Close-Quit) bekommen je eine Exclude-Liste, Rest ist an. Eine gemeinsame Settings-UI: App-Liste mit zwei Spalten/Toggles pro App (Idle / Window-Close) oder zwei simple Listen.
- Issue #10: Background-Prozesse whitelisten können (aktuell nur hartkodierte Apple-Liste in `isBlockedApp`).
- **Bug dabei fixen:** `toggleStatus` ist per `localizedName` gekeyt → bricht bei Sprachwechsel/Umbenennung und kollidiert bei gleichnamigen Apps. Auf `bundleIdentifier` migrieren (mit Migration der bestehenden Daten).

## 3. Zeiteinstellung ohne Stunden/Minuten-Gefummel

Problem: PR #16/#17 + Issues #8/#14 wollen Minuten, aber ein Zahlenfeld mit Einheiten-Picker ist unelegant.

- **Vorschlag: ein einziger Stepper/Slider mit festen, nicht-linearen Stufen:**
  `15 min · 30 min · 1 h · 2 h · 4 h · 8 h · 12 h · 24 h · 48 h`
  Ein Control, keine Einheitenwahl, Anzeige formatiert sich selbst (wie der Energiesparen-Slider in macOS). Deckt sowohl die "Minuten"-Wünsche als auch die bisherigen Stunden-Nutzer ab.
- Migration: bestehendes `hoursUntilClose` auf nächstliegende Stufe mappen.
- Optional später: Per-App-Override (z. B. Browser nie, Vorschau schon nach 15 min).

## 4. Modernisierung (Xcode / macOS)

- Xcode auf aktuelle Version heben (Projekt ist auf LastUpgradeCheck 1430 / Xcode 14.3, Deployment Target 13.0/13.3 inkonsistent → vereinheitlichen, z. B. macOS 14+).
- **Settings komplett neu** (Entscheidung 2026-07-20): SwiftUI `Settings`-Scene statt eigenem `SettingsWindowController` (der `SettingsWindow: NSViewRepresentable`-Rest kann weg), modernes Form-Layout, dort auch die neuen Exclude-Listen unterbringen.
- `LaunchAtLogin`-Package durch natives `SMAppService` ersetzen (seit macOS 13, eine Dependency weniger).
- Swift 6 / Concurrency: Timer-Polling (jede Sekunde!) durch NSWorkspace-Notifications + selteneren Timer (z. B. 30–60 s) ersetzen — spart Energie, gehört in eine "guter macOS-Bürger"-App.
- Design auf macOS 26 anpassen: neues Settings-Layout (Form + `.formStyle(.grouped)`), Menü-Popover-Look, Hover-States via `.buttonStyle` statt manuellem Farb-Gefrickel, SF Symbols konsistent.
- Sortierung im Menü überdenken: nach Restzeit statt alphabetisch? Oder Gruppierung "wird bald beendet" oben.

## 5. Distribution: Release-Pipeline → Homebrew → Sparkle

Stand heute: **Repo hat keine GitHub Releases** — Voraussetzung für beides ist also zuerst eine Release-Pipeline.

1. **Release-Pipeline (Voraussetzung):** Signierter + notarisierter Build (Developer ID, Notarization via `notarytool`) als Zip auf GitHub Releases. Signing passiert auf dem MacBook (kein Apple-Account auf dem Mini). Einmal als Script/Action aufsetzen, dann füttert es Homebrew UND Sparkle.
2. **Homebrew Cask (#1, #3):** Einfach. Cask-Formel ist ~15 Zeilen Ruby, PR an homebrew/homebrew-cask. Notability-Anforderung (≥75 Stars) ist mit 343 locker erfüllt. Updates danach via `brew bump-cask-pr` bzw. Livecheck automatisiert. Alternativ eigener Tap (`BigBerny/homebrew-tap`) ohne Review — sofort live.
3. **Sparkle 2 (#4):** Mittel, aber deutlich einfacher als früher — und weil die App NICHT sandboxed ist, entfällt der fiese XPC-Teil komplett. Schritte: SPM-Dependency, EdDSA-Keys generieren (`generate_keys`), `SUFeedURL` + `SUPublicEDKey` in Info.plist, `SPUStandardUpdaterController` mit stillem Auto-Update (passt zu "man merkt es gar nicht"), `generate_appcast` erzeugt appcast.xml aus dem Release-Ordner, gehostet auf GitHub. Der frühere Fehlversuch war vermutlich Sparkle-1-Ära (DSA-Keys, manuelles Appcast) — heute geradliniger.

## 6. Verworfen (Entscheidungen 2026-07-20)

- Quit-Vorwarnung / Notifications — App soll maximal unsichtbar sein
- Menubar-Icon ausblendbar (#13) — jetzt nicht
- Hide statt Quit (#9) — später vielleicht
- Nur auf Akku beenden (#7), Finder beenden (#15), macOS 12 Support (#12) — nein
- Issue #11 "App Not Working" trotzdem prüfen: vermutlich Gatekeeper/Notarization → löst sich mit der Release-Pipeline

## 7. Housekeeping

- README fehlt komplett (Repo hat nur LICENSE + CHANGELOG) — Screenshots, Install, FAQ (Berechtigungen!).
- Offene PRs beantworten/mergen oder schliessen (#16–#19 sind Vorarbeit für Punkte 1–3).
- Tests: Projekt hat leere Test-Targets; zumindest die Kernlogik (Zeitberechnung, Listen, Migration) testbar machen (Logik aus `ContentView.swift` herauslösen — aktuell ist ALLES in einer Datei).
