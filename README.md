# Radian

Real-time fleet telemetry and dispatch. Drivers stream GPS from a Flutter app, a Go backend
ingests and stores it in TimescaleDB + PostGIS, and a Next.js dashboard renders the live fleet
with MapLibre + deck.gl.

```
Flutter driver app ──(protobuf / WebSocket)──> ingest (Go)
                                                 │ XADD
                                                 ▼
                                          Redis Streams ──> persister (Go) ──COPY──> Timescale + PostGIS
                                                 │
                                                 ▼
                                          broadcast (Go) ──(protobuf / WebSocket)──> Next.js dashboard
```

## Layout

```
Radian/
├── backend/   Go services (ingest, persister, broadcast, api) + fleet simulator
├── web/       Next.js dispatcher dashboard (MapLibre + deck.gl)
├── mobile/    Flutter driver app
├── proto/     Wire contract shared by all three (`make proto`)
└── infra/     docker-compose and SQL migrations
```

Generated protobuf code lives inside each side that uses it: `backend/gen`, `web/src/gen`,
`mobile/lib/gen`.

Local ports: Postgres `5433`, Redis `6380`.

## Getting started

Requires Docker, Go 1.25+ and [buf](https://buf.build/docs/installation).

```bash
cp .env.example .env              # then set JWT_SECRET (openssl rand -hex 32)
make up                           # Postgres + Redis + migrations

# one terminal each
make ingest                       # device WebSocket ingestion on :8081
make persister                    # Redis Streams -> TimescaleDB
make broadcast                    # dashboard fan-out on :8082
make simulator ARGS="-n 1000"     # fake fleet driving around Accra
make web                          # dashboard on http://localhost:3000

curl localhost:8081/metrics
make psql
```

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
| `simulator` | One goroutine per vehicle mimicking the driver app: stationary filter, ack-based buffer, random dead zones with backfill on reconnect. |

Measured locally (Intel MacBook Pro, everything on one machine): 5,000 vehicles at a 2s interval
sustain ~2,100 points/s with ingest at ~0.5 core / 240 MB and the persister writing ~5,800 rows
per 2s flush in ~420 ms. Killing the persister with `SIGKILL` mid-run loses nothing.
