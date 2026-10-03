# Disaster Recovery

- `strategy.md` — written in M11 (`PLAN.md` §9). RPO/RTO targets stated **before** any drill;
  backup/restore vs pilot light vs warm standby vs active-active compared on cost, RPO and RTO;
  why backup/restore was chosen; what data is lost and why that is acceptable; tested results
  (actual vs target, misses included); one Mermaid recovery flow. **Not written yet.**

Recovery points that exist today: RDS automated backups with point-in-time restore (1 day, the
AWS Free plan maximum), a final snapshot on every destroy, and manual snapshots. The dev final
snapshot is restored on every rebuild after the nightly destroy (ADR-015, ADR-026). One real
finding already belongs here: on 2026-10-03, three restores of dev in a row failed with
`InsufficientDBInstanceCapacity` for `db.t4g.micro` on gp2, and dev moved to gp3.

The restore drill (E5) and the full rebuild (E6) are reported in
[`../experiments/`](../experiments/) and summarised here.
