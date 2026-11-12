# Desktop-to-iPhone map

An independent native adaptation of [desktop Sonora](https://github.com/sonorahq/sonora), not a shared Rust runtime or feature-parity port.

| Area | iPhone implementation | Status |
| --- | --- | --- |
| Screens/state | SwiftUI, Observation, async/await | Implemented |
| Playback/system controls | AVPlayer, AVAudioSession, MediaPlayer | Implemented; limited device coverage |
| Local music | Files, AVFoundation metadata, JSON index | Implemented |
| YouTube browsing | HTTP client, parsers, progressive feed | Implemented; unofficial |
| YouTube streams | Guest resolution | Partial; signed-in-only resolution missing |
| Lyrics | LRCLIB, YouTube fallback, line seeking | Implemented |
| History | Persistent local history | Implemented |
| Offline | Ranges, job persistence, smart selection | Implemented; execution constraints |
| Appearance | Themes, typography, icons | Implemented |
| Other providers | Settings placeholders | Not implemented |
| Advanced playback | Gapless, EQ, crossfade, sleep timer | Not implemented |
| Full playlist editing/cloud sync | No corresponding service | Not implemented |

See [architecture](docs/architecture.md) and [limitations](docs/limitations.md). Desktop dependencies do not describe this Swift target.
