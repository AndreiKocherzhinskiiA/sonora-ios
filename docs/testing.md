# Validation and testing

`Package.swift` declares an app target, not an automated test target. There is currently no committed CI workflow. Compiling does not verify audio output, touch behavior, provider access, or every supported OS.

## Build

```sh
bash scripts/deploy.sh build
```

Or build the generated Xcode project on macOS. See [setup](building.md).

## Device checks

Use your own local audio or content you are authorized to access.

| Area | Check |
| --- | --- |
| Local playback | Import, play/pause, seek, skip, background, and lock the phone. |
| Queue | Scroll rows, enter Reorder, move handles, press Done, jump/remove songs. |
| Player | Swipe mini player; double tap cover halves; open pull handle; select Lyrics; minimize. |
| Browsing | Scroll History, Search, collections, Library, Home, and horizontal shelves; check actions. |
| Offline | Complete a download, enable airplane mode, force quit, reopen, and play saved music. |
| Resume | Pause a partial, relaunch, resume, and confirm useful saved progress is retained. |
| Smart downloads | Edit slider without starting; press Start; cancel all; verify saved songs remain and cancelled work stays stopped. |
| Lyrics | Scroll while the song advances, check following yields, then resume following. |
| Interruption | Play other media, close it, and check eligible recovery; manual pauses should remain paused. |
| Accessibility | VoiceOver, larger text, Reduce Motion, light/dark appearance. |

## Evidence and limits

Development included passing xtool builds in WSL and in-place physical-iPhone updates preserving downloads. A user confirmed saved audio in airplane mode and Downloads scrolling after the relevant fixes. These are targeted confirmations, not full regression coverage.

Temporary Swift/HTTP fixtures checked ranges, partial restoration, publication recovery, cancellation, limit persistence, and paths containing spaces. They lived outside this repository and are **not a reproducible checked-in test suite**. Turning them into maintained tests is future work.

Record the commit, iOS version, network condition, and actual observations. Redact personal/account information from evidence.
