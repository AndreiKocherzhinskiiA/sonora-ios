# Changelog

User-visible iPhone changes. Work is unreleased; these describe implemented behavior, not an App Store release.

## [Unreleased]

### Added

- Local imports, persistent library/history, background playback, and system controls.
- YouTube sign-in, Home/search/library browsing, radio, and supported account actions.
- Synced/plain lyrics, line seeking, and following controls.
- Compact/full-screen player, shuffle/repeat, queue actions, and Reorder mode.
- Persistent song/collection downloads with progress, pause/resume, and partial restoration.
- Smart selection of 10-500 distinct recent songs with explicit Start downloads.
- Cancel all downloads, keeping completed songs and stopping refills until restarted.
- Themes, icon packs, typography, and motion preferences.

### Changed

- One player pull handle opens Queue first, with Lyrics inside.
- Double-tap seeking shows direction and seconds feedback.
- Slider edits do not start/change active downloads.
- Home cards retain their original layout and interactions.

### Fixed

- Offline restore/lookups use decoded paths, including Application Support.
- Interrupted download publication recovers without duplicate-file errors.
- Expected connectivity loss pauses transfers without an ordinary offline-state failure.
- History, Search, collections, and Downloads use native lists; rows avoid competing hold gestures.
- Lyric following yields to manual scrolling on iOS 18+.
- Progressive Home loading retains later shelves such as Quick picks.
- Active-tab reselection returns to the root screen.
- Backward seeking, eligible interruption recovery, and bounded network/buffering waits.
