package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"chainledger/internal/workspace"
	"github.com/gin-gonic/gin"
)

type fakeWorkspaceStore struct {
	networks []workspace.Network
	created  workspace.Workspace
	name     string
	network  string
}

func (s *fakeWorkspaceStore) ListNetworks(context.Context) ([]workspace.Network, error) {
	return s.networks, nil
}

func (s *fakeWorkspaceStore) CreateWorkspace(_ context.Context, name, network string) (workspace.Workspace, error) {
	s.name = name
	s.network = network
	return s.created, nil
}

func TestHealth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	NewHandler(nil).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var body map[string]string
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if got := body["status"]; got != "ok" {
		t.Fatalf("status body = %q, want %q", got, "ok")
	}
}

func TestCreateWorkspace(t *testing.T) {
	gin.SetMode(gin.TestMode)
	store := &fakeWorkspaceStore{created: workspace.Workspace{
		ID:        "5a0649f2-04d5-4f9f-b1be-89cc32847350",
		Name:      "Operations",
		Network:   workspace.Network{ID: "sepolia", Name: "Ethereum Sepolia", ChainID: 11155111, NativeSymbol: "ETH", IsTestnet: true},
		CreatedAt: time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC),
	}}
	request := httptest.NewRequest(http.MethodPost, "/v1/workspaces", strings.NewReader(`{"name":" Operations ","network_id":"sepolia"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	NewHandler(store).ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d; body = %s", response.Code, http.StatusCreated, response.Body.String())
	}
	if store.name != "Operations" || store.network != "sepolia" {
		t.Fatalf("CreateWorkspace(%q, %q), want (%q, %q)", store.name, store.network, "Operations", "sepolia")
	}
}
