# Disaster Recovery

- [`strategy.md`](strategy.md) — recovery targets set before the first drill; backup/restore
  compared with pilot light, warm standby and active-active; the planned-teardown data boundary;
  capacity findings; and the recovery flow. Actual RPO/RTO values remain pending.

Recovery points today are RDS automated backups with point-in-time restore (one day, the AWS Free
plan maximum), a final snapshot on every destroy, and manual snapshots. A final snapshot restores
the PostgreSQL database, not the S3 buckets deliberately deleted by `prod-down`.

The restore drill (E5) and full rebuild (E6) are reported in
[`../experiments/`](../experiments/) and summarised in the strategy.
