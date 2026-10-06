# Experiment E6 — Full rebuild from a final snapshot

**Status:** measured 2026-10-06; rebuild succeeded after recovering a scheduled-for-deletion
Redis secret.
**Environment:** prod across Sessions A and B

## Hypothesis

The guarded teardown/rebuild path can restore PostgreSQL rows from the newest final snapshot and
return the application to a healthy state within the pre-committed 45-minute target. Product-image
objects, artifacts, canary output and ALB logs are intentionally outside this recovery boundary.

## Method

At the end of Session A, perform the guarded teardown:

```bash
make CONFIRM_PROD_DOWN=YES prod-down
```

At the start of Session B, restore from the newest available final snapshot:

```bash
make prod-up
```

Record the UTC phase boundaries printed by both commands, final snapshot identifier, first healthy
application response, restored marker/product check, and any capacity failure. Do not call the
rebuild successful merely because Terraform completes: verify application health and restored data.

## Timeline (UTC)

| Time | Event |
|---|---|
| 2026-10-06T17:14:41Z | Final snapshot `prod-cloudforge-db-final-31dbae1e` available |
| not captured | `prod-down` started and completed |
| 2026-10-06T17:18:05Z | `prod-up` started |
| 2026-10-06T17:49:17Z | Terraform rebuild and artifact upload completed |
| after 2026-10-06T17:49:17Z | `/readyz` returned PostgreSQL/Redis `ok`; `/api/products` returned HTTP 200 with `[]` |

## Measurements

- Full-rebuild wall-clock time: not calculable because the `prod-down` boundaries were not
  captured; the measured `prod-up` phase was about 31m12s, within the 45-minute target.
- Planned-teardown RDS RPO: 0 for PostgreSQL rows, using final snapshot
  `prod-cloudforge-db-final-31dbae1e`.
- Restored marker/product integrity: application checks passed; product endpoint returned 200
  with zero rows. No marker was expected in this planned teardown snapshot.
- S3 data confirmed absent by design: the original buckets were destroyed; `prod-up` created a
  new artifacts bucket and rebuilt/uploaded `cloudstore-api/cloudstore-api`.
- Capacity or Terraform failures: first `prod-up` failed because
  `cloudforge/prod/redis-auth` was scheduled for deletion. `restore-secret` followed by a
  Terraform import recovered it; the subsequent `prod-up` completed with 10 resources added,
  1 changed and 0 destroyed.

## What surprised me

The named Redis secret has a 30-day Secrets Manager recovery window, while `prod-down` removes
the Terraform resource. Without a recovery/import preflight, the next `prod-up` fails before it
can rebuild the cache. The preflight is now automated in `scripts/ensure-redis-secret.sh`.

## What I changed as a result

Added the Redis-secret recovery/import preflight to `prod-up`, and verified the rebuilt RDS,
application instance and both health endpoints after the recovery.

## Evidence

Evidence: the `prod-up` output, final snapshot identifier above, and post-run AWS/HTTP checks.
The `prod-down` start/end timestamps were not captured, so only the rebuild phase is timed.
See ADR-018 and `docs/disaster-recovery/strategy.md`.
