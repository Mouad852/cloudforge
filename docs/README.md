# CloudForge technical documentation

This is the deep technical documentation for engineers and interviewers. The root [README](../README.md) is the portfolio overview; this index provides the design rationale, operational evidence, and implementation detail behind it.

## Start with the evidence

| Read | Why it matters |
|---|---|
| [High-level architecture](diagrams/architecture-high-level.md) | The current as-built AWS platform and its explicitly documented trade-offs. |
| [Engineering experiments](experiments/README.md) | Measured load, failure, deployment, recovery, and rebuild results, including limitations. |
| [SEV1 incident review](incidents/2026-09-30-db-password-rotation.md) | A production outage from diagnosis through forced-rotation verification. |

## Architecture and implementation

| Area | Contents |
|---|---|
| [Diagrams](diagrams/README.md) | Current high-level architecture plus network, traffic, data, and security flows. |
| [Infrastructure](infrastructure/README.md) | Terraform implementation and environment-level infrastructure reference. |
| [Architecture decisions](adr/README.md) | 26 recorded design decisions, including superseded decisions retained as history. |
| [Application](../app/README.md) | The intentionally small Go API deployed by the platform. |

## Operating the platform

| Area | Contents |
|---|---|
| [Security](security/README.md) | Threat model, IAM/OIDC, encryption, data handling, incident response, and Well-Architected review. |
| [Observability](observability/README.md) | SLIs, SLOs, error-budget policy, alarms, dashboards, and the synthetic canary. |
| [Runbooks](runbooks/) | Response procedures for alarms, deployments, lifecycle events, and billing. |
| [Disaster recovery](disaster-recovery/README.md) | Recovery objectives, data boundaries, restoration drills, and recovery limits. |

## Evidence and supporting material

| Area | Contents |
|---|---|
| [Resilience](resilience/README.md) | Capacity findings derived from the load-test evidence. |
| [Screenshots](screenshots/README.md) | Visual evidence supporting documented claims. |
| [Cost analysis](cost-analysis.md) | Cost observations and lifecycle economics. |

The documentation records the current as-built architecture. Historical CloudFront-related material is retained where useful, but the current design is a WAF-protected public ALB with no CloudFront distribution; see [ADR-025](adr/025-cloudfront-denied-edge-redesign.md).
