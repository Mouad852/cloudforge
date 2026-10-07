# Disaster Recovery

- [`strategy.md`](strategy.md) — recovery targets set before the first drill; backup/restore
  compared with pilot light, warm standby and active-active; the planned-teardown data boundary;
  capacity findings; and the recovery flow. Point-in-time and full-rebuild actuals are recorded;
  a repeat point-in-time run remains open.

Recovery points today are RDS automated backups with point-in-time restore (one day, the AWS Free
plan maximum), a final snapshot on every destroy, and manual snapshots. A final snapshot restores
the PostgreSQL database, not the S3 buckets deliberately deleted by `prod-down`.

[`../../scripts/restore-test.sh`](../../scripts/restore-test.sh) is the manual point-in-time
restore drill, invoked as `make restore-test RESTORE_ENV=prod`. It writes a marker, restores a
temporary database, checks the marker and product row count through SSM, records capacity
fallbacks, and deletes the temporary instance. The restore drill (E5) and full rebuild (E6) are
reported in
[`../experiments/`](../experiments/) and summarised in the strategy.

## Lifecycle state and drift detection

[`../../scripts/record-lifecycle-state.sh`](../../scripts/record-lifecycle-state.sh) records a
successful lifecycle operation as an explicit GitHub repository variable. The scheduled drift
workflow skips an environment only when that signal says `down` **and** `terraform state list` is
empty. A missing, stale or contradictory signal does not suppress detection.

Setup and recovery: [`../runbooks/environment-lifecycle-state.md`](../runbooks/environment-lifecycle-state.md).
