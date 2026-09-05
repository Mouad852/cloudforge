# Documentation Index

This directory accumulates evidence as CloudForge is built — it is not written after the fact. See [`PLAN.md`](../PLAN.md) for the full roadmap; every milestone there specifies exactly what to capture and where.

| Folder | What lives here |
|---|---|
| [`architecture/`](architecture/) | The system as designed and as built — narrative, linking out to diagrams |
| [`diagrams/`](diagrams/) | Versioned Mermaid/draw.io source for every architecture diagram |
| [`infrastructure/`](infrastructure/) | Terraform module structure, environment strategy, deployment strategies |
| [`security/`](security/) | Threat model, IAM policies, encryption inventory, Well-Architected review |
| [`observability/`](observability/) | SLOs, error budget, dashboards, alarm runbooks |
| [`resilience/`](resilience/) | Scaling behavior, capacity planning, load-test analysis |
| [`disaster-recovery/`](disaster-recovery/) | Backup strategy, RPO/RTO targets and tested results |
| [`experiments/`](experiments/) | One report per game-day experiment — hypothesis, measurements, what changed |
| [`adr/`](adr/) | Architecture Decision Records — the project's decision log |
| [`runbooks/`](runbooks/) | Operational procedures, written to be followed under pressure |
| [`screenshots/`](screenshots/) | Evidence captured at each milestone, organized by phase |
| `cost-analysis.md` | Real Cost Explorer numbers, before/after each optimization |

**Convention:** a folder with no files yet means that phase of the project hasn't happened. Nothing in here is filled in advance of the work — see `PLAN.md` §18 for why that matters.
