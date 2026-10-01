package main

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// A Redis that accepts connections but never answers, the way a node behind a
// dropped security group rule or a hung failover looks to the client. The
// cache must give up quickly and report a miss, so the handler falls back to
// Postgres while the request still has time left.
func TestCacheFailsFastWhenRedisHangs(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { conn.Close() })
		}
	}()

	c := newCache(ln.Addr().String(), "", false, "", newTestLogger())

	start := time.Now()
	_, ok := c.get(context.Background(), "products:list")
	elapsed := time.Since(start)

	if ok {
		t.Fatal("get against a hung Redis reported a hit")
	}
	if elapsed > 2*time.Second {
		t.Fatalf("get took %s; a hung Redis must fail fast, not hold the request", elapsed)
	}
}

// The cache also has to stop at the request's own deadline, which go-redis
// ignores unless ContextTimeoutEnabled is set.
func TestCacheHonoursTheRequestDeadline(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { conn.Close() })
		}
	}()

	c := newCache(ln.Addr().String(), "", false, "", newTestLogger())
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()

	start := time.Now()
	c.get(ctx, "products:list")
	if elapsed := time.Since(start); elapsed > 200*time.Millisecond {
		t.Fatalf("get took %s with a 50ms deadline", elapsed)
	}
}

func TestEveryRequestGetsADeadline(t *testing.T) {
	var deadline time.Time
	var ok bool
	h := withRequestDeadline(requestTimeout, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		deadline, ok = r.Context().Deadline()
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/products", nil))

	if !ok {
		t.Fatal("request context has no deadline")
	}
	if remaining := time.Until(deadline); remaining > requestTimeout || remaining < requestTimeout-time.Second {
		t.Fatalf("deadline is %s away, want about %s", remaining, requestTimeout)
	}
}

// The ALB keeps idle connections to targets open for 60s (its default; the
// edge module does not change it). If the app closed them sooner, the ALB
// could reuse one just as it closes, and the client would get a 502.
func TestServerOutlastsTheALBIdleTimeout(t *testing.T) {
	srv := newHTTPServer(":0", http.NotFoundHandler())

	if srv.IdleTimeout <= 60*time.Second {
		t.Errorf("IdleTimeout %s must be above the ALB's 60s idle timeout", srv.IdleTimeout)
	}
	if srv.ReadHeaderTimeout == 0 || srv.ReadTimeout == 0 || srv.WriteTimeout == 0 {
		t.Error("read and write timeouts must be set; zero means no limit")
	}
	if srv.WriteTimeout <= requestTimeout {
		t.Errorf("WriteTimeout %s must exceed requestTimeout %s, or responses are cut off before the handler times out", srv.WriteTimeout, requestTimeout)
	}
}
