COMPOSE := docker compose --env-file .env -f infra/docker-compose.yml

.PHONY: up down reset migrate psql redis proto proto-lint osrm-data

up:            ## Start Postgres (Timescale+PostGIS), Redis and OSRM; apply migrations
	$(COMPOSE) up -d postgres redis
	$(COMPOSE) run --rm migrate
	@if [ -f infra/osrm/ghana-latest.osrm.mldgr ]; then $(COMPOSE) up -d osrm; \
	 else echo "OSRM data missing: run 'make osrm-data' for road routing (dispatch falls back to estimates)"; fi

OSRM_IMAGE := ghcr.io/project-osrm/osrm-backend:v5.27.1
osrm-data:     ## Download Ghana's road network and build OSRM routing data (~10 min)
	mkdir -p infra/osrm
	curl -L --retry 5 -o infra/osrm/ghana-latest.osm.pbf https://download.geofabrik.de/africa/ghana-latest.osm.pbf
	docker run --rm -v "$(CURDIR)/infra/osrm:/data" $(OSRM_IMAGE) osrm-extract -p /opt/car.lua /data/ghana-latest.osm.pbf
	docker run --rm -v "$(CURDIR)/infra/osrm:/data" $(OSRM_IMAGE) osrm-partition /data/ghana-latest.osrm
	docker run --rm -v "$(CURDIR)/infra/osrm:/data" $(OSRM_IMAGE) osrm-customize /data/ghana-latest.osrm

down:          ## Stop the stack (keeps data)
	$(COMPOSE) down

reset:         ## Stop the stack and wipe all data
	$(COMPOSE) down -v

migrate:       ## Apply pending migrations
	$(COMPOSE) run --rm migrate

psql:          ## Open a psql shell in the database
	$(COMPOSE) exec postgres psql -U radian -d radian

redis:         ## Open a redis-cli shell
	$(COMPOSE) exec redis redis-cli

proto:         ## Generate Go / TS / Dart code from proto/
	cd proto && buf generate

proto-lint:
	cd proto && buf lint

# --- Backend (Go) ---------------------------------------------------------
# Loads .env so services pick up DATABASE_URL, REDIS_URL, JWT_SECRET.
GO_ENV := set -a && . ../.env && set +a &&

.PHONY: api seed ingest persister broadcast geofencer simulator test web mobile-test mobile-e2e-ios

api:           ## Run the REST API (driver login) on :8080
	cd backend && $(GO_ENV) go run ./cmd/api

seed:          ## Create demo drivers, vehicles and zones (password: radian-demo)
	cd backend && $(GO_ENV) go run ./cmd/seed

ingest:        ## Run the telemetry ingestion WebSocket service (:8081)
	cd backend && $(GO_ENV) go run ./cmd/ingest

persister:     ## Run the Redis Streams -> Postgres writer
	cd backend && $(GO_ENV) go run ./cmd/persister

broadcast:     ## Run the dashboard fan-out WebSocket service (:8082)
	cd backend && $(GO_ENV) go run ./cmd/broadcast

geofencer:     ## Detect vehicles entering/leaving zones
	cd backend && $(GO_ENV) go run ./cmd/geofencer

simulator:     ## Drive a fake fleet: make simulator ARGS="-n 500"
	cd backend && $(GO_ENV) go run ./cmd/simulator $(ARGS)

test:
	cd backend && go test ./...

# --- Web (Next.js) ---------------------------------------------------------
web:           ## Run the dispatcher dashboard on :3000
	cd web && npm run dev

# --- Mobile (Flutter) ------------------------------------------------------
mobile-test:   ## Unit tests for the tracking pipeline
	cd mobile && flutter test test/

mobile-e2e-ios: ## Sign in, drive a simulated route, verify delivery (booted iOS simulator)
	mobile/tool/e2e_ios.sh
