# CloudForge Documentation

This is the engineering record for CloudForge: the deployed architecture, the decisions behind it, operational controls, and measured outcomes.

**Recommended reading:** start with the [architecture](diagrams/architecture-high-level.md), then the [SEV1 incident review](incidents/2026-09-30-db-password-rotation.md), [resilience experiments](experiments/README.md), and [Well-Architected review](security/well-architected.md).

| Area | Contents |
|---|---|
| [Diagrams](diagrams/) | Deployed architecture plus network, traffic, data, and security flows |
| [Architecture decisions](adr/) | 26 recorded design decisions and their outcomes |
| [Incident review](incidents/) | Analysis and remediation of a production database-rotation outage |
| [Security](security/) | Threat model, IAM/OIDC controls, encryption, data handling, incident response, and Well-Architected review |
| [Observability](observability/) | SLIs, SLOs, error-budget policy, alarms, and dashboards |
| [Runbooks](runbooks/) | Response procedures for alarms, deployments, lifecycle events, and billing |
| [Experiments](experiments/) | Measured fault injection, deployment, scaling, and recovery exercises |
| [Disaster recovery](disaster-recovery/) | Recovery objectives, backup boundaries, and restoration results |
| [Resilience](resilience/) | Capacity findings derived from load testing |
| [Screenshots](screenshots/) | Selected visual evidence supporting documented claims |
| [Cost analysis](cost-analysis.md) | Cost observations and lifecycle economics |
