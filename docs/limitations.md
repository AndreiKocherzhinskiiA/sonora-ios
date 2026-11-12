# Scope and limitations

An early-stage native iPhone adaptation, not desktop feature parity or an official upstream release.

## Implemented paths

Local imports/playback; background and system controls; compact/full-screen player; queue actions/reordering; Home/search/library collections; artist pages; local history; radio; supported YouTube like/playlist actions; synced/plain lyrics; persistent downloads; configurable smart selection; appearance preferences.

Implementation does not imply exhaustive account, region, device, or OS coverage. See [validation](testing.md).

## Provider restrictions

The YouTube client uses unofficial endpoints and embedded sign-in, which may change or be refused. Browsing uses the signed-in account; stream resolution currently uses a guest client. Tracks requiring a signed-in player, proof-of-origin handling, or player-script resolution can fail. Downloads inherit those restrictions.

Source-code licensing does not grant rights to music, artwork, provider accounts, or service access. Use content/services you are authorized to access and retain. This is not an official Google/YouTube application.

## Offline behavior

- Start downloads applies a limit of 10-500 distinct recent YouTube songs, bounded by available history.
- Slider changes do not alter the active batch. Smart refills use the applied limit until stopped or explicitly changed.
- Cancel all removes pending partials and stops refills until restarted. Completed songs stay saved until removed.
- Transfers run while the app can execute. There is no guaranteed background transfer service or automatic offline playlist synchronization.
- Restored jobs can require Resume. Expiring URLs, host range support, or changed formats can prevent resumption.
- Artwork and lyrics are not persistently cached for offline use.
- Saved audio can play without a provider connection; remote catalog pages still require networking.

## Not implemented

Apple Music, Spotify, Deezer, and Subsonic/Navidrome clients; signed-in-only YouTube stream resolution; gapless playback; EQ; crossfade; sleep timer; scrobbling; full playlist creation/editing; cloud sync.

Other provider names in Settings are placeholders. No app backend, committed automated iOS test target, or CI workflow is declared here.

## Compatibility

Targets iOS 17 and iPhone. Native lyric scroll-phase tracking requires iOS 18+; iOS 17 defaults to manual following controls. The repository contains source and development setup, not an App Store release or hosted signing service.
