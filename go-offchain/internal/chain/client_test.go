package chain

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestBlockNumber(t *testing.T) {
	httpClient := &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusOK,
			Status:     "200 OK",
			Body:       io.NopCloser(strings.NewReader(`{"jsonrpc":"2.0","id":1,"result":"0x2a"}`)),
		}, nil
	})}

	got, err := NewClient("http://rpc.invalid", httpClient).BlockNumber(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got != 42 {
		t.Fatalf("got %d, want 42", got)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
