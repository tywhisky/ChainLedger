# ChainLedger

ChainLedger is an EVM address monitoring and testnet transaction processing platform. It is designed to index ETH and ERC-20 activity for watched addresses; it is not a general-purpose block explorer and must not be used to custody real funds.

The backend uses Gin for HTTP routing while keeping the API, indexer, and worker as independently runnable Go processes.

## Requirements

- Go 1.26+

## Run locally

Each backend process has an independent entry point:

```sh
make run-api
make run-indexer
make run-worker
```

The API listens on `http://localhost:8080` by default. Its current health endpoint is:

```sh
curl http://localhost:8080/healthz
```

Run all backend quality checks with:

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
