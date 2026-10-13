COMPOSE := docker compose --env-file .env -f infra/docker-compose.yml

.PHONY: up down reset migrate psql redis proto proto-lint

up:            ## Start Postgres (Timescale+PostGIS) and Redis, apply migrations
	$(COMPOSE) up -d postgres redis
	$(COMPOSE) run --rm migrate

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

.PHONY: ingest persister simulator test

ingest:        ## Run the telemetry ingestion WebSocket service (:8081)
	cd backend && $(GO_ENV) go run ./cmd/ingest

persister:     ## Run the Redis Streams -> Postgres writer
	cd backend && $(GO_ENV) go run ./cmd/persister

simulator:     ## Drive a fake fleet: make simulator ARGS="-n 500"
	cd backend && $(GO_ENV) go run ./cmd/simulator $(ARGS)

test:
	cd backend && go test ./...
