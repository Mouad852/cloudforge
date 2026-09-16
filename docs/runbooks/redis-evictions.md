# Runbook — Redis evictions occurring

**Alarm:** `dev-cloudforge-redis-evictions`
**Fires when:** `Evictions` > 0 in a 1-minute window — i.e. the very first eviction
trips it.
**Severity:** Investigate soon — not an outage by itself (cache-aside falls back to
origin correctly), but a direct signal the `redis-memory` warning wasn't acted on in
time.

---

## What it means

Redis has run out of memory for new writes and started forcibly removing existing keys
to make room, per its configured eviction policy. Because the app treats Redis as
cache-aside (every value recomputable from RDS/S3), evictions don't corrupt anything —
but every evicted key that's requested again becomes a cache miss, meaning a slower
round-trip to the real origin and increased load on RDS.

## Likely causes

Same root causes as `redis-memory.md` — this alarm is what happens when that warning
wasn't addressed before memory pressure crossed the eviction threshold: an oversized
working set, missing/too-long TTLs, or a key-pattern bug multiplying effective key count.

## Diagnose

1. **ElastiCache → Redis clusters → Monitoring tab** — check `Evictions` alongside
   `DatabaseMemoryUsagePercentage` to confirm they're moving together (expected) rather
   than evictions happening at low memory (which would point at a misconfigured
   `maxmemory` setting instead).
2. Check `rds-cpu` and `rds-connections` for the same window — a spike in evictions often
   shows up as a corresponding spike in RDS load a few seconds later, as cache misses
   force origin fetches.
3. Run `INFO stats` on the Redis node and check `evicted_keys` cumulative count alongside
   `keyspace_misses` to gauge how much traffic is actually being pushed to fall back to
   origin.

## Mitigate

- Same fixes as `redis-memory.md`: add/shorten TTLs, fix key-pattern bugs, or size up the
  node — evictions are memory pressure that's already been acted on by Redis itself, so
  the fix is upstream of Redis, not something to patch at the Redis layer.
- If RDS load is climbing as a direct result (cache misses hammering the origin), that's
  the more urgent half of this — address `rds-cpu`/`rds-connections` if they're trending
  up at the same time, since that's the actual user-facing risk.

## Escalate

If evictions are sustained (not a one-off blip) and RDS load is visibly climbing as a
result, treat this with the same urgency as the RDS alarms it's now driving — a cache
that's evicting under load stops doing its job of protecting the database.

## Verify resolved

No new evictions in the metric window; recovery email arrives automatically. Also
confirm `redis-memory` has settled back under 80%, since evictions will resume as soon as
memory pressure returns if the underlying cause wasn't actually fixed.

## Related

See `redis-memory.md` — always investigate that one alongside this, they're two views of
the same underlying memory pressure.
