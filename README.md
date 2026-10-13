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

# three terminals
make ingest                       # WebSocket ingestion on :8081
make persister                    # Redis Streams -> TimescaleDB
make simulator ARGS="-n 300"      # fake fleet driving around Accra

curl localhost:8081/metrics
make psql
```

## Backend services

| Service | Role |
|---|---|
| `ingest` | Authenticates devices (JWT, vehicle ID comes from the token), validates and time-orders points, `XADD`s batches to `telemetry:raw`, acks the highest seq so the device can prune its buffer. |
| `persister` | Consumer group on `telemetry:raw`. `COPY`s into a staging table, then `INSERT ... ON CONFLICT DO NOTHING` into the hypertable; acks only after commit and replays its pending list after a crash. |
| `simulator` | One goroutine per vehicle mimicking the driver app: stationary filter, ack-based buffer, random dead zones with backfill on reconnect. |

Measured locally (Intel MacBook Pro, everything on one machine): 5,000 vehicles at a 2s interval
sustain ~2,100 points/s with ingest at ~0.5 core / 240 MB and the persister writing ~5,800 rows
per 2s flush in ~420 ms. Killing the persister with `SIGKILL` mid-run loses nothing.
