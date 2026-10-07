# Experiment E5 — Point-in-time database restore

**Status:** one successful production restore drill completed.
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

| Time (UTC) | Event |
|---|---|
| 2026-10-06 14:15:24 | Marker written |
| 2026-10-06 14:22:52 | Latest restorable time includes marker |
| 2026-10-06 14:23:07 | Restore request accepted (`db.t3.micro`, `gp2`, `eu-west-3a`) |
| 2026-10-06 14:41:55 | Temporary instance available |
| 2026-10-06 14:42:00 | Marker and product count verified |
| 2026-10-06 14:43:39 | Temporary instance deleted |

## Measurements

- Marker timestamp and latest restorable time: `2026-10-06 14:15:24Z` to
  `2026-10-06 14:20:10Z`.
- Measured RPO: `286s` (4m46s).
- Restore-ready time: `1141s` (19m01s).
- Marker integrity and product row count: `MARKER_FOUND=1`; `PRODUCT_ROW_COUNT=0`.
- Storage/AZ capacity attempts: `db.t4g.micro` was unavailable for `gp2` and `gp3` in
  `eu-west-3a` and `eu-west-3b`; fallback `db.t3.micro`/`gp2` in `eu-west-3a` succeeded.

## What surprised me

The production restore completed successfully only after falling back from the preferred
`db.t4g.micro` class. The restored instance did not expose a managed secret ARN, so verification
used the source database secret. The product table was empty in this run (`0` rows), which is
consistent with the currently deployed test data but should be rechecked if production is expected
to contain products.

## What I changed as a result

The drill now allows up to 60 minutes for slow RDS restores and records the class, storage type,
and Availability Zone for each capacity attempt. The temporary instance was deleted without a
final snapshot after verification, and the source marker was removed.

## Evidence

Externally stored timeline:
`C:\Users\user\cloudforge-restore-drills\prod-20261006T141326Z-9548\timeline.log`.
The command exited with code `0`; no screenshot was required because the text output was
unambiguous. See ADR-018 and the disaster-recovery strategy.
