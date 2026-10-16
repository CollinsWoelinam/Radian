# Radian Driver (Flutter)

The driver app: sign in, start a shift, and the phone streams GPS to the `ingest` service
until the shift ends, through dead zones, app switches and screen-off.

```bash
make up api ingest persister seed     # backend (separate terminals for the services)
cd mobile
flutter run                           # emulator/simulator: talks to 10.0.2.2 / localhost
flutter run --dart-define=RADIAN_HOST=192.168.1.20   # physical phone on the same Wi-Fi
```

Demo login: `0240000001` / `radian-demo` (see `backend/cmd/seed`).

## How tracking works

```
GPS stream ─▶ MotionDetector ─▶ LocationFilter ─▶ PointBuffer (SQLite) ─▶ Uplink (WebSocket)
   ▲              │ parked? switch to low-power GPS        ▲                 │
   └──────────────┘                                        └── ack(seq) ─────┘ delete acked
```

| Piece | File | Job |
|---|---|---|
| Engine | `lib/tracking/engine.dart` | Wires the pipeline; derives speed/heading when the platform reports 0 |
| Motion | `lib/tracking/motion.dart` | Parked after 2 min within 60 m; wakes on speed or leaving the spot |
| Filter | `lib/tracking/filter.dart` | Drops inaccurate fixes and parked jitter; keep-alive fix every 30 s |
| Buffer | `lib/tracking/point_buffer.dart` | Durable outbox, monotonic `seq`, ring-capped at 50k points |
| Uplink | `lib/tracking/uplink.dart` | Protobuf WebSocket, jittered reconnect, heartbeats, 401 → sign-in |
| Host | `lib/tracking/host.dart` | Android: foreground service (own isolate + notification). iOS: in-process, kept alive by background location |

**Dispatch**: offers arrive over the tracking WebSocket (and a 10 s poll as backup; Android also
shows a heads-up notification). The job card shows a 30 s countdown with Accept/Decline, then the
current stage with **Navigate** (Google Maps / Waze / Apple Maps) and one next-step button.
`integration_test/dispatch_test.dart` runs the whole flow against the local backend.

**Reliability features**

- **Pre-shift checklist** (`lib/tracking/readiness.dart`): location on and allowed (required), plus
  Android notifications, battery-optimisation exemption and brand-specific "keep app running" steps
  for Tecno/Infinix/itel, Xiaomi, Samsung, Huawei and Oppo-family phones, server reachability and
  battery level.
- **GPS glitch filter**: fixes implying > 250 km/h are dropped unless several consistent fixes confirm
  the new position; implausible platform speeds fall back to a derived speed.
- **Shift resume**: an active shift is persisted; if the app or service is killed, reopening the app
  resumes tracking.
- **Token refresh**: the device token is renewed in the background before it expires.

While-in-use location permission is enough on both platforms: the Android location foreground
service and iOS background location updates both continue once started in the foreground.

## Tests

```bash
flutter test test/            # filter, motion detector, SQLite buffer
tool/e2e_ios.sh               # full shift on a booted iOS simulator against the local backend
tool/e2e_android.sh           # same on a running Android emulator
tool/tour.sh ios <udid>       # screenshot every screen into screenshots/ios (or: android <serial>)
tool/tour.sh ios <udid> dispatch_test   # dispatch flow: offer, accept, arrive, complete
```
