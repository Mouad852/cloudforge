# Runbook — RDS free storage low

**Alarm:** `dev-cloudforge-rds-free-storage`
**Fires when:** `FreeStorageSpace` drops below 2 GB.
**Severity:** Page now — RDS goes read-only or refuses writes entirely once storage is
fully exhausted; this is not a "fix it eventually" alarm.

---

## What it means

The instance was provisioned with 20 GB of storage (`allocated_storage`). Below 2 GB
free, the instance is close enough to full that failure is imminent, not hypothetical —
Postgres itself can start rejecting writes once disk is fully exhausted, which is a much
worse failure mode than a slow query.

## Likely causes

- Genuine data growth from normal application use — this is the "good" cause, and means
  it's simply time to grow storage.
- Runaway WAL (write-ahead log) growth, often from a replication slot or backup process
  that's stuck and not letting old WAL segments get cleaned up.
- A bulk import, migration, or accidental duplicate-data bug inflating table size fast.
- Bloat from a table that needs a `VACUUM` (Postgres reclaims space from deleted/updated
  rows lazily — heavy churn without autovacuum keeping up can inflate storage).

## Diagnose

1. **RDS → Databases → dev-cloudforge-db → Monitoring tab** — check the
   `FreeStorageSpace` trend: a slow, steady decline over days points at normal growth; a
   sharp drop in hours points at WAL bloat or a bulk write.
2. Connect to the database and check actual table sizes
   (`SELECT pg_size_pretty(pg_total_relation_size(...))` per table) to find what's
   actually consuming space, if the AWS console trend alone isn't conclusive.
3. Check for long-running or abandoned replication slots (`pg_replication_slots`) — a
   stuck slot prevents WAL cleanup and is a common silent cause of this exact alarm.

## Mitigate

- **RDS storage autoscaling** is the fastest real fix if not already enabled — RDS can
  grow allocated storage automatically up to a ceiling without downtime; check the
  instance's storage configuration.
- Manual **Modify → increase Allocated storage** also works and applies with no downtime
  on RDS, but takes effect on AWS's own schedule (not instant).
- If it's WAL bloat from a stuck replication slot: drop the abandoned slot — freed WAL
  segments are reclaimed shortly after.
- If it's genuine bloat: a targeted `VACUUM` on the affected table(s) can reclaim space
  without needing more storage at all.

## Escalate

If storage keeps declining even after ruling out WAL bloat and confirming it's real data
growth, this needs a capacity-planning decision, not just a one-time bump — repeatedly
resizing under alarm pressure means the growth rate was never actually measured.

## Verify resolved

`FreeStorageSpace` back above 2 GB with margin; recovery email arrives automatically.

## Related

See `rds-cpu.md` and `rds-connections.md` for the other two RDS alarms on this same
instance.
