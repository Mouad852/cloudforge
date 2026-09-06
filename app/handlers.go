package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
)

const maxImageBytes = 5 << 20 // 5 MiB — deliberately trivial prop, not a real upload limit

func (s *server) handleListProducts(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	const cacheKey = "products:list"

	if cached, ok := s.cache.get(ctx, cacheKey); ok {
		writeJSONRaw(w, http.StatusOK, cached)
		return
	}

	products, err := s.store.List(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	body, err := json.Marshal(products)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.cache.set(ctx, cacheKey, string(body))
	writeJSONRaw(w, http.StatusOK, string(body))
}

func (s *server) handleGetProduct(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id := r.PathValue("id")
	cacheKey := "products:" + id

	if cached, ok := s.cache.get(ctx, cacheKey); ok {
		writeJSONRaw(w, http.StatusOK, cached)
		return
	}

	product, err := s.store.Get(ctx, id)
	if errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, err)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	body, err := json.Marshal(product)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.cache.set(ctx, cacheKey, string(body))
	writeJSONRaw(w, http.StatusOK, string(body))
}

func (s *server) handleCreateProduct(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name       string `json:"name"`
		PriceCents int    `json:"price_cents"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.Name == "" || req.PriceCents < 0 {
		writeError(w, http.StatusBadRequest, errors.New("name is required and price_cents must be >= 0"))
		return
	}

	product, err := s.store.Create(r.Context(), req.Name, req.PriceCents)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	s.cache.del(r.Context(), "products:list")
	writeJSON(w, http.StatusCreated, product)
}

func (s *server) handleDeleteProduct(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	if err := s.store.Delete(r.Context(), id); errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, err)
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	s.cache.del(r.Context(), "products:list", "products:"+id)
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handleUploadImage(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	if _, err := s.store.Get(r.Context(), id); errors.Is(err, ErrNotFound) {
		writeError(w, http.StatusNotFound, err)
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxImageBytes+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if len(body) > maxImageBytes {
		writeError(w, http.StatusRequestEntityTooLarge, errors.New("image exceeds 5 MiB"))
		return
	}

	contentType := r.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}

	key, err := s.objects.put(r.Context(), id, contentType, body)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	if err := s.store.SetImageKey(r.Context(), id, key); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	s.cache.del(r.Context(), "products:list", "products:"+id)
	writeJSON(w, http.StatusOK, map[string]string{"image_key": key})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeJSONRaw(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write([]byte(body))
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]string{"error": err.Error()})
}
