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

While-in-use location permission is enough on both platforms: the Android location foreground
service and iOS background location updates both continue once started in the foreground.

## Tests

```bash
flutter test test/            # filter, motion detector, SQLite buffer
tool/e2e_ios.sh               # full shift on a booted iOS simulator against the local backend
```
