package chain

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
)

type Client struct {
	url  string
	http *http.Client
}

func NewClient(url string, httpClient *http.Client) *Client {
	return &Client{url: url, http: httpClient}
}

func (c *Client) BlockNumber(ctx context.Context) (uint64, error) {
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "eth_blockNumber",
		"params":  []any{},
	})
	if err != nil {
		return 0, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.url, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("rpc request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("rpc status: %s", resp.Status)
	}

	var result struct {
		Result string `json:"result"`
		Error  *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, fmt.Errorf("decode rpc response: %w", err)
	}
	if result.Error != nil {
		return 0, fmt.Errorf("rpc error %d: %s", result.Error.Code, result.Error.Message)
	}

	n, err := strconv.ParseUint(result.Result, 0, 64)
	if err != nil {
		return 0, fmt.Errorf("parse block number %q: %w", result.Result, err)
	}
	return n, nil
}
