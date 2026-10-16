#!/usr/bin/env bash
# End-to-end shift test on a running Android emulator against the local backend.
# Usage: tool/e2e_android.sh [emulator-serial]   (backend must be running: make up ingest persister api seed)
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"
SERIAL="${1:-$("$ADB" devices | awk '/^emulator-/{print $1; exit}')}"
PKG=app.radian.radian_driver
[ -n "$SERIAL" ] || { echo "No running emulator. Start one: flutter emulators --launch <id>"; exit 1; }

# A loop around Accra's Ring Road at ~45 km/h: one "lon lat" per second.
route() {
  python3 - <<'PY'
import math
pts = [(5.5600,-0.2310),(5.5700,-0.2200),(5.5718,-0.2075),(5.5690,-0.1950),
       (5.5640,-0.1830),(5.5605,-0.1790),(5.5650,-0.1700),(5.5600,-0.2310)]
def dist(a, b):
    r = math.radians
    dlat, dlon = r(b[0]-a[0]), r(b[1]-a[1])
    h = math.sin(dlat/2)**2 + math.cos(r(a[0]))*math.cos(r(b[0]))*math.sin(dlon/2)**2
    return 2*6371008.8*math.asin(math.sqrt(h))
for a, b in zip(pts, pts[1:]):
    n = max(1, int(dist(a, b) / 12.5))
    for i in range(n):
        t = i / n
        print(f"{a[1]+(b[1]-a[1])*t:.6f} {a[0]+(b[0]-a[0])*t:.6f}")
PY
}

# Each step checks the script is still alive, so no feeder outlives a run
# (two feeders at once make the "vehicle" teleport between them).
PARENT=$$
drive() {
  route | while read -r lon lat; do
    kill -0 "$PARENT" 2>/dev/null || exit 0
    "$ADB" -s "$SERIAL" emu geo fix "$lon" "$lat" >/dev/null
    sleep 1
  done
}
( while kill -0 "$PARENT" 2>/dev/null; do drive; done ) &
DRIVER=$!

trap 'kill $DRIVER 2>/dev/null' EXIT

# Grant runtime permissions up front so no system dialog blocks the test.
# flutter test reinstalls with `adb install -r`, which keeps them. (Granting
# while the app is starting can restart its activity, so do it once, here.)
if ! "$ADB" -s "$SERIAL" shell pm list packages | grep -q "$PKG"; then
  APK=build/app/outputs/flutter-apk/app-debug.apk
  [ -f "$APK" ] || LANG=en_US.UTF-8 flutter build apk --debug
  "$ADB" -s "$SERIAL" install -r "$APK" >/dev/null
fi
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do
  "$ADB" -s "$SERIAL" shell pm grant $PKG android.permission.$p
done
"$ADB" -s "$SERIAL" shell am force-stop $PKG

LANG=en_US.UTF-8 flutter test integration_test/shift_test.dart -d "$SERIAL"
