package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// newTestServer wires a server against the real docker-compose Postgres and
// Redis. Skips if DATABASE_URL isn't set, so `go test ./...` still passes in
// an environment with no compose stack running (e.g. a bare CI checkout
// before `make dev-up`), and runs for real against `make dev-up`.
func newTestServer(t *testing.T) *server {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; run against `make dev-up` to exercise this")
	}

	ctx := context.Background()
	st, err := newStore(ctx, dsn)
	if err != nil {
		t.Fatalf("store: %v", err)
	}
	t.Cleanup(st.Close)

	log := newTestLogger()
	return &server{
		store: st,
		cache: newCache(envOr("REDIS_ADDR", "localhost:6379"), log),
		log:   log,
	}
}

func TestProductLifecycle(t *testing.T) {
	s := newTestServer(t)

	// Create
	createBody := strings.NewReader(`{"name":"Test Widget","price_cents":1999}`)
	req := httptest.NewRequest(http.MethodPost, "/api/products", createBody)
	rec := httptest.NewRecorder()
	s.handleCreateProduct(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: want 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var created Product
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode created product: %v", err)
	}
	if created.Name != "Test Widget" || created.PriceCents != 1999 {
		t.Fatalf("unexpected created product: %+v", created)
	}

	// Get
	req = httptest.NewRequest(http.MethodGet, "/api/products/"+created.ID, nil)
	req.SetPathValue("id", created.ID)
	rec = httptest.NewRecorder()
	s.handleGetProduct(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("get: want 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// List
	req = httptest.NewRequest(http.MethodGet, "/api/products", nil)
	rec = httptest.NewRecorder()
	s.handleListProducts(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list: want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var products []Product
	if err := json.Unmarshal(rec.Body.Bytes(), &products); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	found := false
	for _, p := range products {
		if p.ID == created.ID {
			found = true
		}
	}
	if !found {
		t.Fatalf("created product %s not in list", created.ID)
	}

	// Delete
	req = httptest.NewRequest(http.MethodDelete, "/api/products/"+created.ID, nil)
	req.SetPathValue("id", created.ID)
	rec = httptest.NewRecorder()
	s.handleDeleteProduct(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete: want 204, got %d: %s", rec.Code, rec.Body.String())
	}

	// Get after delete -> 404
	req = httptest.NewRequest(http.MethodGet, "/api/products/"+created.ID, nil)
	req.SetPathValue("id", created.ID)
	rec = httptest.NewRecorder()
	s.handleGetProduct(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("get after delete: want 404, got %d", rec.Code)
	}
}

func TestCreateProductValidation(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest(http.MethodPost, "/api/products", strings.NewReader(`{"name":"","price_cents":100}`))
	rec := httptest.NewRecorder()
	s.handleCreateProduct(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("empty name: want 400, got %d", rec.Code)
	}
}

func TestHealthzNeverTouchesDependencies(t *testing.T) {
	// healthz must be answerable with zero store/cache wiring, since the ALB
	// checks it and it must never depend on Postgres or Redis (ADR-006).
	s := &server{log: newTestLogger()}
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()
	s.handleHealthz(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("healthz: want 200, got %d", rec.Code)
	}
}
