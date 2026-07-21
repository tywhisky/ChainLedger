package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"chainledger/go-offchain/internal/chain"
)

//go:embed openapi.yaml
var openAPI []byte

const swaggerUI = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Go Offchain API</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>SwaggerUIBundle({url: "/openapi.yaml", dom_id: "#swagger-ui"})</script>
</body>
</html>`

func main() {
	rpcURL := env("RPC_URL", "http://127.0.0.1:8545")
	client := chain.NewClient(rpcURL, &http.Client{Timeout: 8 * time.Second})

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /docs", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/docs/", http.StatusMovedPermanently)
	})
	mux.HandleFunc("GET /docs/{$}", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(swaggerUI))
	})
	mux.HandleFunc("GET /openapi.yaml", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		_, _ = w.Write(openAPI)
	})
	mux.HandleFunc("GET /chain/head", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		block, err := client.BlockNumber(ctx)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]uint64{"block_number": block})
	})

	addr := env("ADDR", ":8080")
	log.Printf("listening on %s, rpc=%s", addr, rpcURL)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
