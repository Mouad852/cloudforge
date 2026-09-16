# Runbook — Redis memory usage high

**Alarm:** `dev-cloudforge-redis-memory`
**Fires when:** `DatabaseMemoryUsagePercentage` above 80%, sustained for 5 minutes.
**Severity:** Investigate soon — Redis here is a single node
(`num_cache_clusters = 1`, `automatic_failover_enabled = false`), so there's no
automatic failover if memory pressure eventually causes instability.

---

## What it means

The app uses Redis as a cache-aside layer, not a primary data store — every value in
Redis also exists (or can be recomputed from) RDS/S3. That makes this alarm lower-stakes
than the equivalent RDS alarm: worst case, Redis evicts keys and the app falls back to
the origin, slower but correct. Sustained high memory usage is the leading indicator for
the `redis-evictions` alarm — this one is the early warning, that one is the confirmation
it's already happening.

## Likely causes

- The working set (distinct cached keys in active use) has genuinely grown past what the
  node's memory can hold.
- Keys are being cached without a TTL, or with a TTL too long for how often that data
  actually changes, so old/unused entries pile up instead of expiring.
- A cache key pattern bug — e.g. caching per-user or per-request data under unique keys
  when it should be shared, multiplying the effective key count.

## Diagnose

1. **ElastiCache → Redis clusters → dev-cloudforge-... → Monitoring tab** — check
   `DatabaseMemoryUsagePercentage` trend: gradual growth points at working-set size;
   a sudden jump points at a specific deploy or traffic pattern change.
2. Connect (via an instance with SSM access, since Redis has no public endpoint) and run
   `INFO memory` and `DBSIZE` to see actual key count and memory breakdown.
3. Sample key patterns with `SCAN` (never `KEYS *` against a live instance — it blocks)
   to check whether TTLs are actually being set as expected.

## Mitigate

- If keys are missing TTLs: this is an app-level fix — ensure every cache-aside write
  sets an appropriate expiry.
- If the working set has genuinely outgrown the node: this is a capacity decision
  (bigger node type) — Redis here can't scale out horizontally without adding real
  complexity (clustering), so treat this as a deliberate sizing choice, not a quick knob.
- As an immediate pressure release if evictions are already happening or imminent:
  Redis's own eviction policy handles this automatically (oldest/least-used keys go
  first under `allkeys-lru` or similar) — confirm the configured policy actually matches
  cache-aside usage before assuming eviction alone is "handling it" safely.

## Escalate

If memory keeps climbing after confirming TTLs are set correctly, this is a genuine
capacity/sizing decision, not a bug to keep chasing — flag it for a node-size change.

## Verify resolved

`DatabaseMemoryUsagePercentage` back under 80%; recovery email arrives automatically.

## Related

See `redis-evictions.md` — the natural next symptom if this alarm isn't addressed. Since
`automatic_failover_enabled = false`, there is no standby to fail over to if this single
node becomes unstable; M12's "Redis node failure" game day exists specifically to measure
what that degradation actually looks like end-to-end.
