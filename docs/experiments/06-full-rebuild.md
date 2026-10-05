# Experiment E6 — Full rebuild from a final snapshot

**Status:** prepared, not run.
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
| | `prod-down` started |
| | Final snapshot available |
| | `prod-down` complete |
| | `prod-up` started |
| | Database restored and artifact uploaded |
| | Application healthy and data verified |

## Measurements

- Full-rebuild wall-clock time:
- Planned-teardown RDS RPO:
- Restored marker/product integrity:
- S3 data confirmed absent by design:
- Capacity or Terraform failures:

## What surprised me

Pending the run.

## What I changed as a result

Pending the run.

## Evidence

Pending: Make-target output with UTC phase boundaries and the data/health verification. See
ADR-018 and `docs/disaster-recovery/strategy.md`.
