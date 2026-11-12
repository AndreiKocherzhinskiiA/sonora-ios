# Contributing

Start with the [README](README.md), [build guide](docs/building.md), and [architecture](docs/architecture.md). Desktop Rust commands do not apply here.

## Workflow

1. Make a focused branch and change one behavior at a time.
2. Keep playback/network orchestration in services; views dispatch actions.
3. Reuse Theme and existing controls. Preserve working layouts when fixing gestures.
4. Build with xtool or Xcode and perform relevant [device checks](docs/testing.md).
5. Explain the problem, resulting behavior, validation, and remaining limits in your PR.

Use Conventional Commit subjects such as `fix(player): restore queue scrolling`. Edit `project.yml` and `Package.swift` instead of generated projects. Regenerate PNGs when changing icon SVGs and preserve asset notices.

Prefer native scrolling/buttons inside lists. Avoid broad scroll-detection gestures. Filesystem string paths must be decoded; cancelled work must not overwrite newer state.

## Bugs

Include expected/actual behavior, reproduction, commit/build, iOS version, network condition, and whether local or provider tracks are affected. Share only redacted screenshots/logs, never live credentials or container backups.

## License

Contributions join a GPL-3.0-or-later project; see [COPYING](COPYING). Preserve upstream notices. Share only material you have permission to contribute and include notices for new third-party assets.
