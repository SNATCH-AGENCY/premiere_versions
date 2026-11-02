# Development notes

Technical notes retained from the initial release preparation. For publication steps, see [release setup](RELEASE_SETUP.md).

## Build

Open `Premiere Versions 4.6/Premiere Versions.xcodeproj` in Xcode. Select the **Premiere Versions** scheme and **My Mac**. Current project deployment target: **macOS 26.6.2**. Compatibility with older macOS releases has not been verified.

Before building, run `python3 "Premiere Versions 4.6/tools/enable_sparkle.py"` to download and verify the official SDK. For an already-downloaded archive, pass `--archive /path/to/Sparkle-2.10.1.tar.xz`. Vendor/ is intentionally ignored. See [release setup](RELEASE_SETUP.md). The current local build targets Apple Silicon (arm64).

## Usage

- Launching the app or clicking its Dock icon brings its window to the front. The welcome appears once per new version/build.
- With Premiere Pro frontmost, open with Option+S; choose a project and enter a version. Return opens the optional comment; another Return saves.
- Scroll between version/comment. Escape closes a panel, returns to version, then hides the window; the app keeps running.
- Hover over helper controls or click for immediate access to a temporary panel; use the centered editor for explicit editing actions. Click outside or press Escape to dismiss.
- Settings can enable an optional monochrome menu bar icon; macOS adapts its color. Click opens the app; right-click offers Open and Quit.
- Settings contains the En/Ru language menu, locations, Dock icons, backups and update checks.
- New installs default to English and the graphite icon. Existing locations, shortcuts, icons and user settings are preserved.

## Privacy

Project files, folder access bookmarks, preferences and custom icon history stay in local user storage, outside the repository and app bundle. User-entered project names, comments and versions are never translated.

The app checks the public GitHub-hosted feed silently at launch and every six hours, and when Check updates is chosen. Project paths, project contents and comments are not attached. No analytics or GitHub token is embedded.

Do not commit real projects, user preferences, access bookmarks, build logs or private signing keys. The included audit script checks targeted credential/path patterns and PNG metadata; it is not a complete security audit.

## Testing

Engine, icon history, native Escape routing, localization, appcast handling and native interface checks are in `Premiere Versions 4.6/Tests`. They use temporary fixtures.

## License

A source license has not been selected yet. Public visibility alone does not grant an open-source license.

## Finder icon service

The sandboxed app sends image data to its embedded XPC service. The service is not sandboxed and is deliberately limited to Finder icon metadata on its own installed parent application. It validates the caller executable, owning app identity and exact target, rejects archives and unrelated paths, and preserves quarantine metadata. It exposes no shell command, project-file or general file-write API. The app itself remains sandboxed; no executable-file entitlement is needed.

Before publication, run `Tests/check_icon_quarantine.py /path/to/pristine.app` from normal Terminal. It uses a temporary sandboxed client and an embedded test service to verify icon persistence, unchanged signed Contents, preservation of absent and existing download quarantine, and rejection of other targets. Test-only path allowances are not compiled into production.

## 4.5 verification

Project deletion events, nearest-folder fallback, independent custom slots, Latin shortcut labels, settings scroll expiry, background check coalescing and unchanged-project archive caching have fixture checks. Native AppKit/SwiftUI renders cover both languages. The real icon-XPC and DMG checks run in normal Terminal before publication.

The current app is ad-hoc signed. Its designated requirement changes with code; stable bundle ID and saved bookmarks alone cannot guarantee that macOS privacy approvals survive an update. A stable trusted application-signing identity is a separate distribution decision; Sparkle Ed25519 signatures authenticate update archives, not TCC identity.
