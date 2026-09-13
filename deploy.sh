#!/usr/bin/env bash
# Build the widget and push it to a USB-connected watch over MTP.
#
#   ./deploy.sh              # build for fr265s and install
#   ./deploy.sh fr965        # another device from manifest.xml
#   ./deploy.sh fr265s -w    # extra args go to monkeyc
#
# Needs libmtp (brew install libmtp). Quit OpenMTP / Android File Transfer
# first: only one MTP client can hold the watch at a time.
set -euo pipefail

cd "$(dirname "$0")"

DEVICE="${1:-fr265s}"
shift || true
PRG="bin/PrayerTimes.prg"
DEST="/GARMIN/Apps"   # destination folder; the watch does not list its .prg files over MTP

if ! command -v monkeyc >/dev/null; then
  export PATH="$PATH:$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")bin"
fi
command -v mtp-sendfile >/dev/null || { echo "mtp-sendfile not found: brew install libmtp" >&2; exit 1; }

# Stamp the build with the short commit hash ("+" if the tree has
# uncommitted changes); it shows as "Version" in the on-watch settings menu.
VERSION_XML="resources/strings/version.xml"
VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
git diff --quiet HEAD -- . ":!$VERSION_XML" 2>/dev/null || VERSION="$VERSION+"
trap 'sed -i "" "s|>$VERSION<|>dev<|" "$VERSION_XML"' EXIT
sed -i '' "s|>dev<|>$VERSION<|" "$VERSION_XML"

mkdir -p bin
echo "==> building $VERSION for $DEVICE"
monkeyc -d "$DEVICE" -f monkey.jungle -o "$PRG" -y developer_key.der "$@"

echo "==> looking for the watch"
if ! (mtp-detect 2>&1 || true) | grep -i garmin >/dev/null; then
  echo "no Garmin MTP device found. Plug the watch in, quit OpenMTP, then retry." >&2
  exit 1
fi

# Same filename as before, so the watch treats it as an update and keeps
# the app's settings and storage. The second argument is the folder: libmtp
# would otherwise try to resolve the name to an existing file id, and the
# watch hides installed .prg files from MTP listings.
echo "==> sending $PRG -> $DEST/"
mtp-sendfile "$PRG" "$DEST" 2>&1 | grep -v 'extended association'

echo "done. Unplug the watch; the widget reloads on its own."
