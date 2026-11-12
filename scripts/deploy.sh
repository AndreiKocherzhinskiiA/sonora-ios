#!/usr/bin/env bash
# Copies the iOS project to the Linux filesystem and builds or installs it with xtool.
#
#   ./scripts/deploy.sh            build, sign and install on the connected iPhone
#   ./scripts/deploy.sh build      build only
#
# Run it inside WSL. The copy is needed because the compiler cannot rename files on /mnt/c.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/sonora-ios"
MODE="${1:-install}"

export PATH="$HOME/.local/bin:$HOME/.local/share/swiftly/bin:$PATH"
# shellcheck disable=SC1091
. "$HOME/.local/share/swiftly/env.sh"

mkdir -p "$DEST"
rsync -a --delete \
  --exclude .build --exclude xtool --exclude .bsp --exclude preview \
  "$SRC/" "$DEST/"
cd "$DEST"

case "$MODE" in
  build)
    xtool dev build
    ;;
  install)
    if ! idevice_id -l | grep -q .; then
      echo "No iPhone visible. Start the usbmuxd bridge (see HANDOFF.md, step 4)." >&2
      exit 1
    fi
    xtool dev
    ;;
  *)
    echo "usage: $0 [build|install]" >&2
    exit 2
    ;;
esac
