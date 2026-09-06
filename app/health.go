package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"time"

	"github.com/aws/aws-sdk-go-v2/feature/ec2/imds"
)

// healthz is shallow on purpose — 200 if the process can answer HTTP at all.
// This is the check the ALB uses (ADR-006); it must never depend on Postgres
// or Redis, or one dependency outage would take every instance out of rotation.
func (s *server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

// readyz is deep — it actually pings Postgres and Redis. Monitored, but the
// ALB never calls it, so a slow dependency degrades monitoring, not traffic.
func (s *server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	status := struct {
		Postgres string `json:"postgres"`
		Redis    string `json:"redis"`
	}{Postgres: "ok", Redis: "ok"}

	healthy := true

	if err := s.store.Ping(ctx); err != nil {
		status.Postgres = err.Error()
		healthy = false
	}
	if err := s.cache.Ping(ctx); err != nil {
		status.Redis = err.Error()
		// Redis failing does not fail readiness — the app fails open to
		// Postgres for reads, so a dead cache is degraded, not down.
	}

	w.Header().Set("Content-Type", "application/json")
	if !healthy {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	json.NewEncoder(w).Encode(status)
}

// whoami exists to visually demonstrate load balancing on video: hit it
// enough times behind the ALB and the instance ID alternates across AZs.
func (s *server) handleWhoami(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 500*time.Millisecond)
	defer cancel()

	instanceID, az := "local-dev", "local-dev"
	client := imds.New(imds.Options{})

	if out, err := client.GetMetadata(ctx, &imds.GetMetadataInput{Path: "instance-id"}); err == nil {
		instanceID = readAllClose(out.Content)
	}
	if out, err := client.GetMetadata(ctx, &imds.GetMetadataInput{Path: "placement/availability-zone"}); err == nil {
		az = readAllClose(out.Content)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"instance_id":       instanceID,
		"availability_zone": az,
	})
}

// readAllClose is only reachable on a real EC2 instance (IMDSv2 responding),
// so a read failure here can't happen in local dev — the caller already
// fell back to "local-dev" before ever calling this.
func readAllClose(rc io.ReadCloser) string {
	defer rc.Close()
	b, _ := io.ReadAll(rc)
	return string(b)
}
