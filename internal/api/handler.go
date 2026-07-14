package api

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"chainledger/internal/workspace"
	"github.com/gin-gonic/gin"
)

type workspaceStore interface {
	ListNetworks(context.Context) ([]workspace.Network, error)
	CreateWorkspace(context.Context, string, string) (workspace.Workspace, error)
}

type handler struct {
	workspaces workspaceStore
}

func NewHandler(workspaces workspaceStore) *gin.Engine {
	router := gin.New()
	router.Use(gin.Recovery())
	router.GET("/healthz", health)

	h := handler{workspaces: workspaces}
	v1 := router.Group("/v1")
	v1.GET("/networks", h.listNetworks)
	v1.POST("/workspaces", h.createWorkspace)
	return router
}

func health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h handler) listNetworks(c *gin.Context) {
	networks, err := h.workspaces.ListNetworks(c.Request.Context())
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", "unable to list networks")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": networks})
}

type createWorkspaceRequest struct {
	Name      string `json:"name" binding:"required,max=100"`
	NetworkID string `json:"network_id" binding:"required"`
}

func (h handler) createWorkspace(c *gin.Context) {
	var request createWorkspaceRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_request", "name and network_id are required")
		return
	}

	request.Name = strings.TrimSpace(request.Name)
	request.NetworkID = strings.TrimSpace(request.NetworkID)
	if request.Name == "" || request.NetworkID == "" {
		respondError(c, http.StatusBadRequest, "invalid_request", "name and network_id are required")
		return
	}

	created, err := h.workspaces.CreateWorkspace(c.Request.Context(), request.Name, request.NetworkID)
	if errors.Is(err, workspace.ErrNetworkNotFound) {
		respondError(c, http.StatusBadRequest, "unsupported_network", "selected network is not supported")
		return
	}
	if err != nil {
		respondError(c, http.StatusInternalServerError, "internal_error", "unable to create workspace")
		return
	}
	c.JSON(http.StatusCreated, gin.H{"data": created})
}

func respondError(c *gin.Context, status int, code, message string) {
	c.JSON(status, gin.H{"error": gin.H{"code": code, "message": message}})
}
