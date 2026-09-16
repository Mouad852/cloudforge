# Runbook — RDS connection count high

**Alarm:** `dev-cloudforge-rds-connections`
**Fires when:** average `DatabaseConnections` above ~80% of `db.t4g.micro`'s
`max_connections` (threshold: 90), sustained for 10 minutes.
**Severity:** Page now — once `max_connections` is actually reached, every *new*
connection attempt is refused outright, which looks like a full outage to the app.

---

## What it means

`db.t4g.micro` caps out around ~112 concurrent connections (instance-class dependent,
computed from available memory). This alarm fires at 90 — a deliberate margin before the
hard wall, so there's still time to act before new connections start failing outright.

## Likely causes

- A connection leak in the app — connections opened but never returned to the pool
  (e.g. on an error path that skips cleanup).
- The app's connection pool size, multiplied by the number of running instances, is
  simply too close to the database's actual ceiling — a scale-out event on the app tier
  (more EC2 instances) directly increases total connection demand on the *one* shared
  database.
- A slow query holding a connection open far longer than normal, backing up the pool.

## Diagnose

1. **RDS → Databases → dev-cloudforge-db → Monitoring tab** — check whether
   `DatabaseConnections` correlates with `ec2-cpu`/ASG scale-out events (more app
   instances = more pooled connections against the same database) or looks unrelated to
   traffic (pointing at a leak).
2. Connect and run `SELECT count(*), state FROM pg_stat_activity GROUP BY state;` —
   a large number stuck in `idle in transaction` is the classic leak signature.
3. Check `rds-cpu` for the same window — a slow query saturating CPU will also hold its
   connection open longer than normal, compounding both alarms together.

## Mitigate

- If it's a leak: this is an app-level fix (ensure connections are always released, even
  on error paths) — not something infrastructure can patch around.
- If it's a slow query holding connections open: identify and fix the query (see
  `rds-cpu.md`'s Performance Insights step) — connections free up once it stops running
  long.
- If it's simply too many app instances against too small a connection ceiling: this is
  a capacity-planning question (smaller per-instance pool size, a connection pooler like
  RDS Proxy, or a bigger instance class) — not a same-minute fix.

## Escalate

If connections are climbing toward the wall with no obvious leak or slow query, treat it
as a capacity limit being reached for real and flag it — letting the app hit
`max_connections` fully means every new request fails, not just a slow one.

## Verify resolved

`DatabaseConnections` back under the threshold with margin; recovery email arrives
automatically.

## Related

See `rds-cpu.md` and `rds-free-storage.md` for the other two RDS alarms on this same
instance.
