# Documentation Index

This directory accumulated as CloudForge was built; it was not written after the fact. See
[`PLAN.md`](../PLAN.md) for the as-built summary and the remaining work.

**Start here:** the [SEV1 incident review](incidents/2026-09-30-db-password-rotation.md), the
[Well-Architected review](security/well-architected.md), [ADR-025](adr/025-cloudfront-denied-edge-redesign.md)
and the [as-built architecture](diagrams/architecture-high-level.md).

| Folder | What lives here | State |
|---|---|---|
| [`diagrams/`](diagrams/) | As-built architecture, network, traffic, data and security flows (Mermaid) | current |
| [`adr/`](adr/) | Architecture Decision Records, the decision log | 26 ADRs, current |
| [`incidents/`](incidents/) | Post-incident reviews of real outages | 1 (SEV1, 2026-09-30) |
| [`security/`](security/) | Threat model, IAM walkthrough, OIDC trust policy, encryption inventory, data classification, incident response, Well-Architected review | current |
| [`observability/`](observability/) | SLOs, SLIs and the error-budget policy | current; error-budget snapshot measured through 2026-10-06 |
| [`runbooks/`](runbooks/) | One runbook per alarm, deployment and rollback, readiness checklist, account teardown | current |
| [`experiments/`](experiments/) | One report per game day | E1–E6 measured; E7 optional |
| [`disaster-recovery/`](disaster-recovery/) | DR strategy, RPO/RTO targets and tested results | point-in-time restore and full rebuild measured; repeat restore remains open |
| [`resilience/`](resilience/) | Capacity planning from load tests | E3 measured; generator-bounded conclusion recorded |
| [`infrastructure/`](infrastructure/) | Deployment strategies compared | optional (M13) |
| [`screenshots/`](screenshots/) | Selected evidence, by milestone | partial by design |
| [`cost-analysis.md`](cost-analysis.md) | Real Cost Explorer numbers | prod run-rate measured; resting-cost window remains open |

**Convention:** nothing here is filled in ahead of the work. A folder marked "planned" means
that phase hasn't happened yet.
