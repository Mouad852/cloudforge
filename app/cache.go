package main

import (
	"context"
	"crypto/tls"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
)

const productTTL = 60 * time.Second

type cache struct {
	rdb *redis.Client
	log *slog.Logger
}

// newCache connects to Redis directly (empty authToken, useTLS=false) for
// local dev's unauthenticated docker-compose instance, or with the
// ElastiCache AUTH token and TLS enabled in deployed environments (M6) -
// transit_encryption_enabled on the replication group requires TLS, the
// plain redis:// protocol is refused.
//
// tlsServerName is deliberately separate from addr: addr is our own Route 53
// private-zone CNAME (cache.cloudforge.internal, ADR-013 - keeps app config
// decoupled from AWS-generated hostnames), but ElastiCache's certificate is
// issued for its own generated hostname, not our CNAME. Go's TLS client
// verifies the certificate against whatever hostname it's told to expect
// (ServerName), which defaults to addr's host if left unset - so without
// this, every connection attempt fails hostname verification. Dialing one
// name while verifying against another is exactly what ServerName is for.
func newCache(addr, authToken string, useTLS bool, tlsServerName string, log *slog.Logger) *cache {
	opts := &redis.Options{
		Addr:     addr,
		Password: authToken,
	}
	if useTLS {
		opts.TLSConfig = &tls.Config{
			MinVersion: tls.VersionTLS12,
			ServerName: tlsServerName,
		}
	}
	return &cache{
		rdb: redis.NewClient(opts),
		log: log,
	}
}

func (c *cache) Ping(ctx context.Context) error {
	return c.rdb.Ping(ctx).Err()
}

// get returns (value, true) on a cache hit, ("", false) on a clean miss,
// and ("", false) with a logged warning on a Redis error — the caller falls
// through to Postgres either way. This is the "fails open" behavior required
// by PLAN.md: a dead cache degrades latency, not availability.
func (c *cache) get(ctx context.Context, key string) (string, bool) {
	val, err := c.rdb.Get(ctx, key).Result()
	switch {
	case err == nil:
		return val, true
	case err == redis.Nil:
		return "", false
	default:
		c.log.Warn("cache get failed, falling through to postgres", "key", key, "error", err)
		return "", false
	}
}

func (c *cache) set(ctx context.Context, key, val string) {
	if err := c.rdb.Set(ctx, key, val, productTTL).Err(); err != nil {
		c.log.Warn("cache set failed", "key", key, "error", err)
	}
}

func (c *cache) del(ctx context.Context, keys ...string) {
	if err := c.rdb.Del(ctx, keys...).Err(); err != nil {
		c.log.Warn("cache invalidation failed", "keys", keys, "error", err)
	}
}
