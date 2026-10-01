package main

import (
	"bytes"
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

	version, err := migrateWithRetry(cfg.DatabaseURL, log)
	if err != nil {
		log.Error("migrations failed", "error", err)
		os.Exit(1)
	}
	log.Info("schema up to date", "version", version)

	st, err := newStore(ctx, cfg.DatabaseURL, cfg.DBPassword)

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
		cache:   newCache(cfg.RedisAddr, cfg.RedisAuthToken, cfg.RedisTLS, cfg.RedisTLSServerName, log),
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
	mux.HandleFunc("GET /api/products/{id}/image", s.handleGetImage)

	httpServer := newHTTPServer(":"+cfg.Port,
		withRequestLogging(log, withSecurityHeaders(withRequestDeadline(requestTimeout, mux))))

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

// requestTimeout bounds the work behind one request: every Postgres, Redis
// and S3 call made with the request's context gives up at this point. It is
// well under the ALB's 60s idle timeout, so a hung dependency gets a fast 5xx
// from the app and frees its pool connection, instead of holding it until the
// ALB gives up on the request (M10, Well-Architected REL 5).
const requestTimeout = 10 * time.Second

// newHTTPServer sets the timeouts net/http leaves at zero (no limit):
//   - ReadHeaderTimeout and ReadTimeout stop a client that sends a request
//     slowly from holding a connection open; 30s covers a 5 MiB image upload.
//   - WriteTimeout caps the whole response, past requestTimeout.
//   - IdleTimeout must stay above the ALB's 60s idle timeout, so the ALB is
//     always the side that closes an idle keep-alive connection. Left unset,
//     it would fall back to ReadTimeout (30s), and the ALB would sometimes
//     send a request on a connection the app had just closed: a 502.
func newHTTPServer(addr string, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       75 * time.Second,
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

		attrs := []any{
			"request_id", reqID,
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		}
		// The response body of a 5xx is writeError's {"error": "..."}. Without
		// it in the log, the only record of why a request failed went to the
		// client: during the 2026-09-30 outage the logs showed 500s and
		// nothing else.
		if rec.status >= http.StatusInternalServerError {
			attrs = append(attrs, "error", rec.errorBody.String())
		}
		log.Info("request", attrs...)
	})
}

// maxLoggedErrorBytes caps how much of a 5xx body goes into the log line.
const maxLoggedErrorBytes = 512

type statusRecorder struct {
	http.ResponseWriter
	status    int
	errorBody bytes.Buffer
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if r.status >= http.StatusInternalServerError {
		if room := maxLoggedErrorBytes - r.errorBody.Len(); room > 0 {
			r.errorBody.Write(b[:min(len(b), room)])
		}
	}
	return r.ResponseWriter.Write(b)
}

func newRequestID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}
