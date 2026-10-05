# Experiment E5 — Point-in-time database restore

**Status:** prepared, not run.
**Environment:** prod during Session A

## Hypothesis

RDS point-in-time recovery can restore a marker row and the product-table contents within the
pre-committed RTO target of 60 minutes. The marker timestamp versus `LatestRestorableTime` gives a
measured RPO; a successful database instance alone is not proof of integrity.

## Method

Run the manual drill twice on different days:

```bash
make restore-test RESTORE_ENV=prod
```

The script writes a source marker through SSM, waits until the restorable time includes it,
restores a temporary instance, verifies the marker and product row count through SSM, records every
storage/AZ capacity attempt outside the repository, and deletes the temporary instance.

## Timeline (UTC)

| Time | Event |
|---|---|
| | Marker written |
| | Latest restorable time includes marker |
| | Restore request accepted |
| | Temporary instance available |
| | Marker and product count verified |
| | Temporary instance deleted |

## Measurements

- Marker timestamp and latest restorable time:
- Measured RPO:
- Restore-ready time:
- Marker integrity and product row count:
- Storage/AZ capacity attempts:

## What surprised me

Pending the run.

## What I changed as a result

Pending the run.

## Evidence

Pending: the externally stored drill timeline and one integrity-check screenshot only if the text
output is ambiguous. See ADR-018 and the disaster-recovery strategy.
