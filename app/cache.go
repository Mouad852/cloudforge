package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
)

const productTTL = 60 * time.Second

type cache struct {
	rdb *redis.Client
	log *slog.Logger
}

func newCache(addr string, log *slog.Logger) *cache {
	return &cache{
		rdb: redis.NewClient(&redis.Options{Addr: addr}),
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
