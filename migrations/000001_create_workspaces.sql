CREATE TABLE networks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    chain_id BIGINT NOT NULL UNIQUE CHECK (chain_id > 0),
    native_symbol TEXT NOT NULL,
    is_testnet BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO networks (id, name, chain_id, native_symbol, is_testnet)
VALUES ('sepolia', 'Ethereum Sepolia', 11155111, 'ETH', TRUE);

CREATE TABLE workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 100),
    network_id TEXT NOT NULL REFERENCES networks (id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX workspaces_network_id_idx ON workspaces (network_id);
