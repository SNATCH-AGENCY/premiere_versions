# Distribution status

Official Sparkle 2.10.1 was verified by its published SHA-256 and linked. The private update key was created using the official tool in macOS Keychain; only its public value is in AppMetadata.plist. Distribution preflight passes.

Pending: complete the normal-Terminal signing and isolated two-build update test, review public files, choose a source license, then publish the first archive and appcast. No feed or release has been uploaded.

## Next version: deliberate click navigation

User reported accidental hover expansion, panel switching and layout jumps. Do not fold this redesign into the 4.91 save fix. Prepare a visual sketch before implementation.

- Hover highlights/scales triggers only; it never opens, switches or dismisses panels.
- Click opens a panel; repeat click on its trigger dismisses it; another trigger deliberately switches panels.
- Escape and outside click dismiss; pointer departure does not.
- Preserve independent main-page trigger anchors and settings-origin routing positions.
- Settings-only sections expand downward on full-row click with a clear chevron. Keep essential controls visible.
- Avoid automatic scroll, unsolicited sibling collapse and content jumps. Retain the clicked header's visual position.
- Preserve control drag safety, Reduce Motion and a consistent restrained transition.
