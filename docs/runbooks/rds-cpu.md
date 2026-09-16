# Runbook — RDS CPU saturation

**Alarm:** `dev-cloudforge-rds-cpu`
**Fires when:** RDS `CPUUtilization` above 80%, sustained for 5 minutes.
**Severity:** Investigate soon — the instance is `db.t4g.micro`, `multi_az = false`, so
there's no automatic failover to fall back on; this is the single instance the app
depends on.

---

## What it means

Unlike the app tier, RDS can't horizontally scale out under this alarm — there's one
instance, and it's a small burstable-performance class (`db.t4g.micro`). Sustained high
CPU usually means either a genuinely expensive query pattern or the instance has burned
through its CPU credit balance (t-class instances are credit-based, not flat-rate).

## Likely causes

- One or more slow/unindexed queries running repeatedly.
- A spike in traffic driving proportionally more queries — check the app's request
  volume for the same window.
- CPU credit exhaustion — `db.t4g.micro` is burstable; sustained load can deplete the
  credit balance, after which performance degrades further, not just CPU showing high.
- A connection storm forcing excessive query planning overhead — check
  `rds-connections` for the same window.

## Diagnose

1. **RDS → Databases → dev-cloudforge-db → Monitoring tab** — check `CPUUtilization`
   alongside `CPUCreditBalance` (if graphed) to see whether credits are being consumed.
2. **RDS → Performance Insights** (if enabled) — identifies the specific top SQL
   statements consuming CPU, which is far faster than guessing from app logs.
3. Cross-check the Golden Signals dashboard's Traffic widget — is this proportional to
   request volume, or is CPU high while traffic is flat (pointing at a query regression)?

## Mitigate

- If it's one bad query: this is an app-level fix — add an index, or cache the result in
  Redis instead of hitting RDS every time.
- If it's proportional to a genuine traffic increase: this is a capacity conversation
  (bigger instance class), not an emergency action — `db.t4g.micro` has a low ceiling by
  design (dev/portfolio budget, PLAN.md §4).
- If CPU credits are exhausted: there's no quick fix except reduced load — this is the
  clearest signal the instance class needs revisiting.

## Escalate

If Performance Insights points at a specific query and it can't be fixed quickly (no
easy index, needs an app-side change), treat this as a data-tier capacity risk and flag
it rather than letting the alarm keep re-firing silently.

## Verify resolved

`CPUUtilization` back under 80%; recovery email arrives automatically.

## Related

See `rds-connections.md` and `rds-free-storage.md` for the other two RDS alarms on this
same instance — all three point at the same underlying constraint: one small, single-AZ
database with no automatic failover.
