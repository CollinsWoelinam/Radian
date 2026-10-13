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

```bash
cp .env.example .env
make up      # Postgres + Redis + migrations
make psql
```
