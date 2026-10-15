#!/usr/bin/env bash
# Runs the screen tour and screenshots each screen into ./screenshots/<platform>/.
# Usage: tool/tour.sh ios <simulator-udid> | tool/tour.sh android <emulator-serial>
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM=$1 DEVICE=$2
OUT="screenshots/$PLATFORM"; mkdir -p "$OUT"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

shot() {
  if [ "$PLATFORM" = ios ]; then xcrun simctl io "$DEVICE" screenshot "$OUT/$1.png" >/dev/null 2>&1
  else "$ADB" -s "$DEVICE" exec-out screencap -p > "$OUT/$1.png"; fi
  echo "captured $1"
}

LOG=$(mktemp)
if [ "$PLATFORM" = ios ]; then
  # Reuse the E2E harness for route + permissions, but run the tour test.
  sed 's#integration_test/shift_test.dart#integration_test/tour_test.dart#' tool/e2e_ios.sh > "$LOG.sh"
else
  sed 's#integration_test/shift_test.dart#integration_test/tour_test.dart#' tool/e2e_android.sh > "$LOG.sh"
fi
chmod +x "$LOG.sh"; cp "$LOG.sh" tool/.tour_runner.sh
trap 'rm -f tool/.tour_runner.sh "$LOG.sh"' EXIT

tool/.tour_runner.sh "$DEVICE" 2>&1 | tee "$LOG" | while IFS= read -r line; do
  case "$line" in *TOUR:*) shot "${line##*TOUR:}";; *"All tests passed"*|*"Some tests failed"*) echo "$line";; esac
done
