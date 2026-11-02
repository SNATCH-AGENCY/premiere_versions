# 4.5 Build 1

- **Project selection:** a dedicated screen, clearer navigation and reliable handling of missing or moved projects.
- **Icons and appearance:** a compact picker, two new built-in styles, removable custom icons and the option to hide the Dock icon.
- **Keyboard shortcuts:** clearer setup and English key labels when recording a shortcut.
- **Updates:** quiet checks at launch and every six hours, with subtle indicators. You choose when to install.
- **Interface refinements:** softer blur transitions, cleaner help controls and short-term memory for the Settings scroll position.
- **Optimization:** reduced background activity, fewer repeated archive checks and no animation polling while the utility is hidden.

# 4.4 Build 2

- A drag-and-drop DMG for first-time installation.
- Improve update reliability around persistent application icons.

# 4.4 Build 1

- Optional, persistent monochrome menu bar icon that follows macOS appearance. Click to open; right-click to open or quit.
- Clarify that the save shortcut opens the utility from active Premiere Pro.
- Ease the version/comment transition in and out over 0.86 seconds, with synchronized scroll hints and delayed text focus.

# 4.3 Build 4

- Clarify that the save shortcut opens the utility from active Premiere Pro.
- Ease the version/comment transition in and out over 0.86 seconds, with synchronized scroll hints and delayed text focus.

# 4.3 · Build 2

- Main helper panels open only on hover; clicking their triggers no longer opens or pins them.
- Settings opened from Help's Check updates action and the custom logo editor are centered in the application window.
- Custom logo colors use an embedded hue/saturation wheel, value rail and screen eyedropper instead of RGB sliders. Tile/letter selection and in-place icon history remain unchanged.

# 4.3 · Build 1 — local preview

- English and Russian UI, remembered across launches and updates. English is the default. The Russian design keeps its English hints; user-entered content is never translated. A compact En/Ru menu lives in Settings.
- Fixed utility window size; zoom/full-screen disabled. Header branding returns to the version stage and gently enlarges on hover.
- Temporary hover panels cover their trigger and dismiss on pointer exit; clicking pins them. Escape and outside click dismiss panels. Escape returns from comment to version, then hides the window; repeated presses are debounced.
- Welcome animates only while the real window is visible and active. Longer coordinated camera transition to the version stage. Click the Help logo to replay it.
- Help uses the header mark, omits creator credits, starts at the top and has a persistent scrollbar.
- Monitoring uptime uses days/hours/minutes with singular/plural forms.
- Edit either selected custom icon in place without rotating the other history slot. New colors use an embedded RGB editor; no separate macOS color panel remains.
- One update-check service backs Help and Settings. Help opens pinned Settings at Updates. Successful check timestamps are saved only after a valid server response; missing feeds/network failures are shown honestly.
- Release feed URL prepared for pewakkk/premiere_versions. The verified official Sparkle 2.10.1 SDK and a Keychain-generated public update key are linked. Publication remains gated on signed artifacts and an actual two-build integration test.
- Machine bundle build is 4.3.1; the UI remains 4.3 · Build 1. This keeps Sparkle comparisons monotonic while visible build numbers reset per version.
