#!/usr/bin/env bash
# End-to-end shift test on an iOS simulator against the local backend.
# Usage: tool/e2e_ios.sh [simulator-udid]   (backend must be running: make up ingest persister api seed)
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${1:-$(xcrun simctl list devices booted -j | python3 -c 'import sys,json; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v))')}"
BUNDLE=app.radian.radianDriver

# Drive a loop around Accra's Ring Road at ~45 km/h.
xcrun simctl location "$SIM" clear
xcrun simctl location "$SIM" start --speed=12.5 --distance=8 \
  5.5600,-0.2310 5.5700,-0.2200 5.5718,-0.2075 5.5690,-0.1950 \
  5.5640,-0.1830 5.5605,-0.1790 5.5650,-0.1700 5.5600,-0.2310 >/dev/null

# flutter test reinstalls the app, which resets its location permission and
# would leave a native prompt the test can't tap. Keep it granted meanwhile.
( while true; do xcrun simctl privacy "$SIM" grant location-always "$BUNDLE" 2>/dev/null || true; sleep 1; done ) &
GRANTER=$!
trap 'kill $GRANTER 2>/dev/null; xcrun simctl location "$SIM" clear' EXIT

LANG=en_US.UTF-8 flutter test integration_test/shift_test.dart -d "$SIM"
