package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type server struct {
	store   *store
	cache   *cache
	objects *objectStore
	log     *slog.Logger
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	ctx := context.Background()

	cfg, err := loadConfig(ctx)
	if err != nil {
		log.Error("config load failed", "error", err)
		os.Exit(1)
	}

	st, err := newStore(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Error("store init failed", "error", err)
		os.Exit(1)
	}
	defer st.Close()

	objects, err := newObjectStore(ctx, cfg)
	if err != nil {
		log.Error("object store init failed", "error", err)
		os.Exit(1)
	}

	s := &server{
		store:   st,
		cache:   newCache(cfg.RedisAddr, log),
		objects: objects,
		log:     log,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	mux.HandleFunc("GET /whoami", s.handleWhoami)
	mux.HandleFunc("GET /api/products", s.handleListProducts)
	mux.HandleFunc("POST /api/products", s.handleCreateProduct)
	mux.HandleFunc("GET /api/products/{id}", s.handleGetProduct)
	mux.HandleFunc("DELETE /api/products/{id}", s.handleDeleteProduct)
	mux.HandleFunc("POST /api/products/{id}/image", s.handleUploadImage)

	httpServer := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: withRequestLogging(log, mux),
	}

	go func() {
		log.Info("listening", "port", cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	// Drain on SIGTERM: stop accepting new connections, let in-flight
	// requests finish, for longer than the ALB's deregistration delay
	// (M4, 30s) so no request is cut off mid-response during a deploy.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop

	log.Info("shutting down", "drain_timeout", cfg.DrainTimeout)
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.DrainTimeout)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Error("graceful shutdown failed", "error", err)
	}
}

// withRequestLogging assigns a request ID and emits one structured JSON log
// line per request — the metric-filter source for M7's CloudWatch alarms.
func withRequestLogging(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		reqID := newRequestID()
		w.Header().Set("X-Request-Id", reqID)

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		log.Info("request",
			"request_id", reqID,
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func newRequestID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}
