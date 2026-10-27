<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/radian-logo-dark.svg">
    <img src="docs/brand/radian-logo-light.svg" alt="Radian" width="300">
  </picture>
</p>

<p align="center"><strong>Real-time fleet telemetry &amp; dispatch.</strong><br>
See every vehicle live, and send the nearest driver by real drive time.</p>

Drivers stream GPS from a Flutter app, a Go backend ingests and stores it in TimescaleDB +
PostGIS, and a Next.js dashboard renders the live fleet with MapLibre + deck.gl.

![Dispatcher dashboard: a job offered to the nearest driver, with the live route to pickup and drop-off](docs/screenshots/web-dispatch-dark.jpg)

## Screenshots

### Dispatcher dashboard

| | |
|---|---|
| ![Sign-in](docs/screenshots/web-signin.jpg) | ![Zones with live "vehicles inside" counts, light theme](docs/screenshots/web-zones-light.jpg) |
| **Sign in.** The brand panel's rings echo the dispatch search radius. | **Zones** (depots, service areas, restricted areas) with live counts of the vehicles inside. |
| ![A restricted-zone alert and the activity feed](docs/screenshots/web-alerts-dark.jpg) | ![Creating a job: pickup and drop-off clicked on the map](docs/screenshots/web-new-job-light.jpg) |
| **Alerts.** Entering a restricted zone or leaving the service area raises a toast; every crossing lands in the feed. | **New job.** Click the pickup and drop-off on the map; it goes to the nearest driver by drive time, then the next on a decline or timeout. |

### Driver app

<table>
  <tr>
    <td width="25%"><img src="docs/screenshots/app-signin-ios.png" alt="Driver app sign-in on Night Ink"></td>
    <td width="25%"><img src="docs/screenshots/app-checklist-android.png" alt="Pre-shift checklist on Android, dark theme"></td>
    <td width="25%"><img src="docs/screenshots/app-on-shift-ios.png" alt="On shift and live, light theme"></td>
    <td width="25%"><img src="docs/screenshots/app-end-shift-ios.png" alt="End shift confirmation"></td>
  </tr>
  <tr>
    <td><b>Sign in</b> (iOS). The header shrinks while you type so Sign in stays on screen.</td>
    <td><b>Before you start</b> (Android). Fixes for location, battery saver and the phone maker's background limits.</td>
    <td><b>On shift.</b> The amber pulse is you: the live vehicle on the dispatcher's map.</td>
    <td><b>End shift</b> with a summary, so a shift is never ended by accident.</td>
  </tr>
</table>

<p align="center"><img src="docs/screenshots/app-job-offer.png" alt="A job offer with a countdown, and a job in progress" width="420"><br>
<sub><b>Jobs.</b> An offer counts down before it goes to the next driver; once accepted, the card walks the driver through each stop.</sub></p>

The phone screens come from the integration-test tour, which signs in, drives a simulated route
and ends the shift: `mobile/tool/tour.sh ios <simulator-udid>` (or `android <serial>`), with the
backend running.

## Architecture

```
Flutter driver app ──(protobuf / WebSocket)──> ingest (Go) <── job offers (Redis Pub/Sub) ── api (Go)
                                                                                           │ dispatch:
                                                                                           │ PostGIS KNN + OSRM drive times
Flutter driver app ──(protobuf / WebSocket)──> ingest (Go)
                                                 │ XADD
                                                 ▼
                                          Redis Streams ──> persister (Go) ──COPY──> Timescale + PostGIS
                                                 │      └──> geofencer (Go) ── zone enter/exit ──┐
                                                 ▼                                               ▼
                                          broadcast (Go) ──(protobuf / WebSocket)──> Next.js dashboard
```

## Brand

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/brand/radian-logo-dark.svg">
  <img src="docs/brand/radian-logo-light.svg" alt="Radian logo" width="200">
</picture>

The mark, the **Sweep**, is a sector exactly one radian wide: its arc is as long as its radius.
It reads as dispatch sweeping a search radius from an origin and landing on the nearest live
vehicle, the amber dot. Night Ink `#0B1220`, Radian Blue `#2563EB`, Signal `#4F8BFF` (the mark on
dark), Live Amber `#F59E0B` (the live vehicle, plus the on-job status and warnings; never a background) and Paper `#F6F8FB`; type is Geist with
Geist Mono for plates, coordinates and counts. The mark is drawn in code on both sides
(`web/src/components/Brand.tsx`, `mobile/lib/ui/brand.dart`), so it stays sharp at every size.

## Layout

```
Radian/
├── backend/   Go services (ingest, persister, broadcast, geofencer, api) + fleet simulator
├── web/       Next.js dispatcher dashboard (MapLibre + deck.gl)
├── mobile/    Flutter driver app
├── proto/     Wire contract shared by all three (`make proto`)
└── infra/     docker-compose and SQL migrations
```

Generated protobuf code lives inside each side that uses it: `backend/gen`, `web/src/gen`,
`mobile/lib/gen`.

Local ports: Postgres `5434`, Redis `6380`.

## Getting started

Requires Docker, Go 1.25+ and [buf](https://buf.build/docs/installation).

```bash
cp .env.example .env              # then set JWT_SECRET (openssl rand -hex 32)
make osrm-data                    # once: Ghana road network for routing (~10 min)
make up                           # Postgres + Redis + OSRM + migrations
make seed                         # demo accounts and zones (password: radian-demo)

# one terminal each
make api                          # REST: sign-in, jobs, dispatch on :8080
make ingest                       # device WebSocket ingestion on :8081
make persister                    # Redis Streams -> TimescaleDB
make broadcast                    # dashboard fan-out on :8082
make geofencer                    # zone enter/exit alerts
make simulator ARGS="-n 1000"     # fake fleet driving around Accra
make web                          # dashboard on http://localhost:3000

curl localhost:8081/metrics
make psql
```

## Dispatch

1. A dispatcher creates a job on the dashboard (click pickup and optional drop-off on the map).
2. The api finds available vehicles near the pickup: online in the last 2 minutes, with a driver
   assigned, not already on or offered a job, within 30 km (PostGIS `ST_DWithin` + KNN `<->`).
3. It ranks them by **road drive time** using OSRM's table service (falls back to a straight-line
   estimate if OSRM is down) and offers the job to the fastest one for 30 seconds.
4. The offer reaches the driver's phone via Redis Pub/Sub → ingest → WebSocket (plus a REST poll as
   a safety net) and an Android heads-up notification.
5. Decline or timeout → the next-best vehicle. No one available → retried every 15 s.
6. The driver works the job: accept → arrived → (to drop-off) → complete. Every step lands in a
   `job_events` timeline, and dashboards are told to refresh via `JobsChanged` pushes.

Row locks (`FOR UPDATE` / `SKIP LOCKED`) keep this safe with several api instances; a partial
unique index guarantees a vehicle can only have one active job.

Demo logins: dashboard `dispatch@radian.dev`, driver app `0240000001`, password `radian-demo`.
The simulator's drivers accept ~85% of offers and drive real roads, so dispatch can be watched
end to end.

## Geofences

Dispatchers draw zones on the dashboard (click the corners, then click the first corner to close
the outline). There are three kinds, and each decides what counts as an alert:

| Kind | Alert | Logged only |
|---|---|---|
| Restricted | a vehicle **enters** | exits |
| Service area | a vehicle **leaves** | entries |
| Depot | none | arrivals and departures |

The `geofencer` reads `telemetry:raw` in its own consumer group and tests each fix against the zones
in memory (bounding box first, then point-in-polygon). GPS noise at a boundary would otherwise
cause a burst of enter/exit pairs, so a fix only counts when it is farther from the edge than its
own accuracy, and a crossing needs two such fixes in a row. Confirmed crossings go to
`geofence_events` (with a unique index so a replay after a crash is a no-op). Who is inside each
zone right now is kept in Redis sets, which give the dashboard its live counts and let a restart
pick up where it left off. Alerts reach dashboards through broadcast as toasts, a pulse on the
map and an activity feed.

PostGIS validates every outline (`ST_IsValid`), so a self-crossing shape is rejected with a clear
message instead of producing wrong results later.

## Web dashboard

Next.js + MapLibre (OpenFreeMap tiles, no API key) + deck.gl. Fleet state lives outside React in a
mutable store; a `requestAnimationFrame` loop interpolates every vehicle between fixes and pushes
fresh layers to deck.gl, while React re-renders the panels at 2 Hz. Markers are sized in meters
(clamped in pixels) so the fleet stays readable from city to street zoom.

## Backend services

| Service | Role |
|---|---|
| `ingest` | Authenticates devices (JWT, vehicle ID comes from the token), validates and time-orders points, `XADD`s batches to `telemetry:raw`, acks the highest seq so the device can prune its buffer. |
| `persister` | Consumer group on `telemetry:raw`. `COPY`s into a staging table, then `INSERT ... ON CONFLICT DO NOTHING` into the hypertable; acks only after commit and replays its pending list after a crash. |
| `broadcast` | Tails the stream (plain `XREAD`, so every instance sees everything), keeps the latest fix per vehicle, and once a second sends each dashboard only the vehicles that changed inside its viewport. Slow clients are resynced with a snapshot instead of buffering. |
| `geofencer` | Second consumer group on `telemetry:raw`; turns fixes into confirmed zone crossings (see Geofences). |
| `simulator` | One goroutine per vehicle mimicking the driver app: stationary filter, ack-based buffer, random dead zones with backfill on reconnect. |

Measured locally (Intel MacBook Pro, everything on one machine): 5,000 vehicles at a 2s interval
sustain ~2,100 points/s with ingest at ~0.5 core / 240 MB and the persister writing ~5,800 rows
per 2s flush in ~420 ms. Killing the persister with `SIGKILL` mid-run loses nothing.
