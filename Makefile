.PHONY: build test check run-api run-indexer run-worker

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
	go run ./cmd/api

run-indexer:
	go run ./cmd/indexer

run-worker:
	go run ./cmd/worker
