.PHONY: build test check run-api run-indexer run-worker frontend-install run-frontend frontend-build db-create migrate

DATABASE_URL ?= postgres://postgres:postgres@localhost:5432/chainledger?sslmode=disable
GO_PACKAGES = ./cmd/... ./internal/...

build:
	go build $(GO_PACKAGES)

test:
	go test $(GO_PACKAGES)

check:
	go fmt $(GO_PACKAGES)
	go vet $(GO_PACKAGES)
	go test $(GO_PACKAGES)
	go build $(GO_PACKAGES)
	npm --prefix frontend run build

run-api:
	DATABASE_URL="$(DATABASE_URL)" go run ./cmd/api

run-indexer:
	go run ./cmd/indexer

run-worker:
	go run ./cmd/worker

frontend-install:
	npm --prefix frontend install

run-frontend:
	npm --prefix frontend run dev

frontend-build:
	npm --prefix frontend run build

db-create:
	PGPASSWORD=postgres createdb --host=localhost --port=5432 --username=postgres --owner=postgres chainledger

migrate:
	psql "$(DATABASE_URL)" -v ON_ERROR_STOP=1 -f migrations/000001_create_workspaces.sql
