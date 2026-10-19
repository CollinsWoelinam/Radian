#!/usr/bin/env bash
# Real-phone background tracking check. Usage:
#   RADIAN_HOST=<mac-lan-ip> tool/background_android.sh <serial>
# Prints when each phase started; count stored points per phase afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
SERIAL=$1
PKG=app.radian.radian_driver

LANG=en_US.UTF-8 flutter test integration_test/background_test.dart -d "$SERIAL" \
  ${RADIAN_HOST:+--dart-define=RADIAN_HOST=$RADIAN_HOST} 2>&1 | tee "${FULL_LOG:-/tmp/radian_background_full.log}" | while IFS= read -r line; do
  case "$line" in
    *TOUR:bg-home*)  echo "PHASE home  $(date -u +%H:%M:%S)"; "$ADB" -s "$SERIAL" shell input keyevent KEYCODE_HOME ;;
    *TOUR:bg-sleep*) echo "PHASE sleep $(date -u +%H:%M:%S)"; "$ADB" -s "$SERIAL" shell input keyevent KEYCODE_SLEEP ;;
    *TOUR:bg-wake*)  echo "PHASE wake  $(date -u +%H:%M:%S)"
                     "$ADB" -s "$SERIAL" shell input keyevent KEYCODE_WAKEUP
                     "$ADB" -s "$SERIAL" shell wm dismiss-keyguard 2>/dev/null || true
                     "$ADB" -s "$SERIAL" shell am start -n "$PKG/.MainActivity" >/dev/null ;;
    *TOUR:bg-done*)  echo "PHASE done  $(date -u +%H:%M:%S)" ;;
    *TOUR:timeout*)  echo "TIMEOUT $(date -u +%H:%M:%S)"; "$ADB" -s "$SERIAL" exec-out screencap -p > /tmp/radian_bg_timeout.png ;;
    *"All tests passed"*|*"Some tests failed"*|*"radian.tracker"*) echo "$line" ;;
  esac
done
