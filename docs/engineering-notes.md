# Engineering notes

Mobile-specific work in this repository builds on desktop Sonora's product and visual origins.

## Files existed, but offline playback still went online

Saved tracks appeared in the UI while airplane-mode playback attempted a provider request. Device logs confirmed that route. Read-only container inspection found valid AAC audio; two saved files fully decoded with ffmpeg.

URL-based file operations worked, but `URL.path()` supplied an encoded `Application%20Support` string to an API expecting `Application Support`. Local existence checks therefore failed.

The correction uses `path(percentEncoded: false)` for filesystem string checks. A temporary fixture initially missed it because its directory had no spaces; using an Application Support directory reproduced the failure. After correction, the user confirmed existing songs played in airplane mode and device logs showed file-backed playback.

## Scroll fixes need narrow scope

A short custom hold gesture competed with scrolling. Downloads moved to a native List and omitted that recognizer. History and other row-heavy screens adopted the same pattern.

A broader card change also altered Quick picks even though Home worked. That visual change was reverted. Home keeps its original cards; rows keep menu buttons. The lesson: fix the failing surface without redesigning one that already works.

## Configuration is separate from execution

Moving the smart-limit slider initially began transfers. The implementation now separates configured limit, applied limit, and running state. Start applies a selection; Cancel all persists a stopped state and preserves finished audio. Expensive work becomes explicit while later refills can still follow the applied configuration.

## Tradeoffs

JSON persistence is simple, but some file work remains synchronous. Bounded ranges preserve partial progress but cannot guarantee background execution or survive every host format change. Unofficial provider support is incomplete. These remain measurement and validation work, not claims of production readiness.
