# ChainLedger

ChainLedger is an EVM address monitoring and testnet transaction processing platform. It is designed to index ETH and ERC-20 activity for watched addresses; it is not a general-purpose block explorer and must not be used to custody real funds.

The backend uses Gin for HTTP routing while keeping the API, indexer, and worker as independently runnable Go processes.

## Requirements

- Go 1.26+
- PostgreSQL and its `psql` command-line client

## Run locally

With PostgreSQL running on its default port and the local `postgres` user using password `postgres`, create the project database once and apply the migration:

```sh
make db-create
make migrate
```

Start the API. The Makefile uses `postgres://postgres:postgres@localhost:5432/chainledger` by default:

```sh
make run-api
```

Override `DATABASE_URL` when a different local connection is needed.

The API listens on `http://localhost:8080`. Create a workspace by selecting the supported Sepolia network:

```sh
curl http://localhost:8080/v1/networks

curl -X POST http://localhost:8080/v1/workspaces \
  -H 'Content-Type: application/json' \
  -d '{"name":"My Workspace","network_id":"sepolia"}'
```

The other backend processes still have independent entry points:

```sh
make run-indexer
make run-worker
```

Run all backend checks with:

```sh
make check
```

## Repository layout

```text
cmd/          API, indexer, and worker process entry points
internal/     Private application and domain packages
frontend/     Web application (introduced in a later roadmap step)
migrations/   Ordered PostgreSQL migrations
openapi/      REST API contract
deploy/       Local and production deployment files
docs/         Architecture and product documentation
```

See [roadmap.md](roadmap.md) for the implementation plan.
