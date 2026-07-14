package workspace

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNetworkNotFound = errors.New("network not found")

type Network struct {
	ID           string `db:"id" json:"id"`
	Name         string `db:"name" json:"name"`
	ChainID      int64  `db:"chain_id" json:"chain_id"`
	NativeSymbol string `db:"native_symbol" json:"native_symbol"`
	IsTestnet    bool   `db:"is_testnet" json:"is_testnet"`
}

type Workspace struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Network   Network   `json:"network"`
	CreatedAt time.Time `json:"created_at"`
}

type Store struct {
	db *pgxpool.Pool
}

func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) ListNetworks(ctx context.Context) ([]Network, error) {
	rows, err := s.db.Query(ctx, `
		SELECT id, name, chain_id, native_symbol, is_testnet
		FROM networks
		ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	networks, err := pgx.CollectRows(rows, pgx.RowToStructByName[Network])
	if err != nil {
		return nil, err
	}
	return networks, nil
}

func (s *Store) CreateWorkspace(ctx context.Context, name, networkID string) (Workspace, error) {
	var result Workspace
	err := s.db.QueryRow(ctx, `
		WITH workspace AS (
			INSERT INTO workspaces (name, network_id)
			SELECT $1, id FROM networks WHERE id = $2
			RETURNING id, name, network_id, created_at
		)
		SELECT workspace.id, workspace.name, workspace.created_at,
		       networks.id, networks.name, networks.chain_id,
		       networks.native_symbol, networks.is_testnet
		FROM workspace
		JOIN networks ON networks.id = workspace.network_id`, name, networkID).Scan(
		&result.ID,
		&result.Name,
		&result.CreatedAt,
		&result.Network.ID,
		&result.Network.Name,
		&result.Network.ChainID,
		&result.Network.NativeSymbol,
		&result.Network.IsTestnet,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return Workspace{}, ErrNetworkNotFound
	}
	return result, err
}
