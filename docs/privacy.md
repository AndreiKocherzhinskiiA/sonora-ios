# Privacy and local data

This describes the checked-in implementation, not the privacy policies of Google, LRCLIB, Apple, or other providers.

## Device storage

Imported music, downloads, pending transfers, and listening history live in the app sandbox under Application Support. Appearance and smart-download settings use UserDefaults. Lyrics use an in-memory cache.

YouTube sign-in uses a nonpersistent WebKit data store. The resulting cookie header is saved in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Deezer sign-in captures or accepts your `arl` cookie and stores only that token in Keychain with the same accessibility level. Subsonic / Navidrome sign-in stores your server URL, username, salt, and salted MD5 token in Keychain with the same accessibility level (your raw password is not saved). No credentials belong in repository files. Signing out removes the saved Keychain session, but does not clear local history or downloads.

## External requests

The provider clients contact YouTube Music (for account browsing, search, mutations, lyrics, and stream URLs), Deezer (for account browsing, search, favorites/playlist updates, and encrypted stream URLs), and your configured Subsonic / Navidrome server (for library browsing, search, cover art, and audio streams). LRCLIB receives song metadata for lyrics matching. Artwork is fetched from metadata-supplied URLs. Those services receive your network address and request data under their own policies.

No dedicated Sonora iOS backend or analytics SDK is declared in this project. This does not mean external providers or the OS collect no data. Errors and track-related diagnostics can appear in system logs.

## Managing data

Remove downloaded songs through their song actions. Cancel all removes pending partials while keeping completed audio. Clear history from its page. Sign out from Settings to remove the saved provider session. Uninstalling normally removes sandbox data, but Keychain has a separate lifecycle: sign out explicitly if you want to remove that session.

Never publish cookies, Keychain exports, container backups, signing material, device identifiers, or unredacted logs. See [security reporting](../SECURITY.md).
