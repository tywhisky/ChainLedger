# Architecture

ChainLedger starts as a modular monolith with separate API, indexer, and worker processes backed by PostgreSQL. Shared implementation belongs under `internal`; process-specific orchestration stays with its command.

The process boundary is intentional, but the repository remains a single Go module until measured deployment or ownership needs justify a split.

The first vertical slice stores workspaces in PostgreSQL. A workspace selects one supported EVM network; the initial release exposes only Ethereum Sepolia, matching the one-testnet boundary in the roadmap. Authentication and workspace membership are deferred until the identity boundary is defined.
