# Radian dashboard

Dispatcher dashboard: MapLibre basemap (OpenFreeMap) with a deck.gl overlay fed by the
`broadcast` service over a protobuf WebSocket.

```bash
cp .env.example .env.local   # NEXT_PUBLIC_BROADCAST_URL
npm install                  # also copies the MapLibre worker into public/maplibre/
npm run dev
```

- `src/lib/fleet-store.ts`: live vehicle state and per-frame interpolation (outside React)
- `src/lib/fleet-socket.ts`: reconnecting WebSocket, viewport subscriptions
- `src/components/FleetMap.tsx`: map + render loop
- `src/components/Dashboard.tsx`: panels, search, selection, follow mode
- `src/gen/`: generated from `proto/` with `make proto`; don't edit
