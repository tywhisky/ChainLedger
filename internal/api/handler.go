package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func NewHandler() *gin.Engine {
	router := gin.New()
	router.Use(gin.Recovery())
	router.GET("/healthz", health)
	return router
}

func health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
