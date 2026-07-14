.PHONY: build test check run-api run-indexer run-worker db-create migrate

DATABASE_URL ?= postgres://postgres:postgres@localhost:5432/chainledger?sslmode=disable

build:
	go build ./...

test:
	go test ./...

check:
	go fmt ./...
	go vet ./...
	go test ./...
	go build ./...

run-api:
	DATABASE_URL="$(DATABASE_URL)" go run ./cmd/api

run-indexer:
	go run ./cmd/indexer

run-worker:
	go run ./cmd/worker

db-create:
	PGPASSWORD=postgres createdb --host=localhost --port=5432 --username=postgres --owner=postgres chainledger

migrate:
	psql "$(DATABASE_URL)" -v ON_ERROR_STOP=1 -f migrations/000001_create_workspaces.sql
