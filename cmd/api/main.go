package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"chainledger/internal/api"
	"chainledger/internal/workspace"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		logger.Error("DATABASE_URL is required")
		os.Exit(1)
	}

	databaseContext, cancelDatabase := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelDatabase()
	database, err := pgxpool.New(databaseContext, databaseURL)
	if err != nil {
		logger.Error("database configuration failed", "error", err)
		os.Exit(1)
	}
	defer database.Close()
	if err := database.Ping(databaseContext); err != nil {
		logger.Error("database connection failed", "error", err)
		os.Exit(1)
	}

	server := &http.Server{
		Addr:              ":8080",
		Handler:           api.NewHandler(workspace.NewStore(database)),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			logger.Error("API shutdown failed", "error", err)
		}
	}()

	logger.Info("API started", "address", server.Addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Error("API stopped", "error", err)
		os.Exit(1)
	}
}
