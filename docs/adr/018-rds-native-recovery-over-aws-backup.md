# ADR-018: RDS-native recovery over AWS Backup

**Status:** accepted   **Date:** 2026-10-05   **Milestone:** M11

## Context

CloudForge runs on an AWS Free plan with a one-day RDS automated-backup retention limit and a
credit-saving, ephemeral production lifecycle (D1). The required M11 outcome is not a particular
backup product: it is proof that PostgreSQL data can be restored, its integrity verified, and its
RPO and RTO measured. Terraform already creates a final RDS snapshot on destroy, `prod-up`
restores the newest final snapshot, and RDS provides point-in-time recovery while an instance
exists.

AWS Backup would add a vault and backup plan, but that additional service alone would not prove a
restore. It is useful only if it supplies a recovery capability that RDS-native backups and a
tested drill do not provide, such as retaining recovery points beyond the Free plan's one-day RDS
limit.

## Decision

Use RDS-native recovery as the mandatory M11 path:

- RDS automated backups and point-in-time restore cover unplanned database loss.
- A final RDS snapshot is required for every planned database destroy.
- `make prod-down` and `make prod-up` are the executable planned-teardown and rebuild path.
- `scripts/restore-test.sh` will restore a temporary database, verify a marker row and row count,
  record timings, and remove the temporary instance.

AWS Backup remains NICE work, to be adopted only if it adds a demonstrated capability beyond this
path. Cross-Region snapshot copy is also NICE, not a claim that CloudForge has Region-loss
recovery.

## Alternatives considered

- **AWS Backup now** — deferred. It adds cost and configuration without replacing the required
  restore proof; it becomes worthwhile if longer retention or another distinct capability is
  needed.
- **Manual snapshots before every destroy** — rejected. A manual step can be forgotten; the
  Terraform database lifecycle structurally requires a final snapshot.
- **Pilot light, warm standby, or active-active recovery** — rejected. Each keeps duplicate
  infrastructure running or needs multi-Region data replication, which conflicts with D1 and the
  remaining credit balance.

## Consequences

The recovery boundary is explicit: a planned teardown restores PostgreSQL rows, but intentionally
deletes product images, application artifacts, canary output, and ALB logs. The application binary
is rebuilt from the repository. This is acceptable for CloudForge's non-customer portfolio data
and is documented in the [recovery strategy](../disaster-recovery/strategy.md) and
[data classification](../security/data-classification.md).

Capacity is part of the measured recovery result. Dev snapshot restores have failed for
`db.t4g.micro` with both gp2 and gp3 because no suitable Availability Zone capacity was available.
The restore script must record each instance-class, storage-type and Availability-Zone attempt,
use documented fallbacks, and report failed capacity attempts rather than presenting a recovery
time as universal.
No RPO or RTO actual is claimed until the drill succeeds.
