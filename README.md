# CloudForge

[![Terraform](https://github.com/Mouad852/cloudforge/actions/workflows/terraform.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/terraform.yml)
[![Application](https://github.com/Mouad852/cloudforge/actions/workflows/app.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/app.yml)
[![Drift detection](https://github.com/Mouad852/cloudforge/actions/workflows/drift.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/drift.yml)

**CloudForge is a production-style AWS platform built with Terraform, delivered through GitHub Actions, and validated through real incident response and resilience experiments.** The Go API is intentionally small; the focus is infrastructure engineering, operational judgment, and evidence.

![CloudForge architecture](docs/diagrams/assets/architecture-high-level-generated-v2.png)

## At a glance

| Area | Implementation |
|---|---|
| Infrastructure | Terraform modules for networking, edge, compute, database, cache, storage, observability, and CI/CD |
| AWS platform | VPC across two AZs, WAF-protected ALB, Auto Scaling Groups, RDS PostgreSQL, ElastiCache Redis, S3, Secrets Manager, CloudWatch, and Route 53 private DNS |
| Delivery | GitHub Actions with OIDC, approval-gated applies, policy checks, Terraform-native tests, rolling deployments, and a k6 verification gate |
| Operations | SLOs, CloudWatch alarms, synthetic canary, per-alarm runbooks, daily drift detection, and an explicit ephemeral-environment lifecycle |
| Resilience | Tested instance replacement, cache failure, load/scaling, rolling deployment, point-in-time recovery, and full environment rebuild |

## Architecture

Traffic reaches a regional AWS WAF and Application Load Balancer. The ALB fronts an Auto Scaling
Group within a two-AZ VPC. The application connects privately to PostgreSQL and Redis, retrieves
credentials from Secrets Manager, and stores artifacts, images, and ALB logs in private S3
buckets.

The deployed design deliberately favors a bounded personal AWS budget: one application instance at rest (scaling to two), Single-AZ RDS, a NAT instance, and ephemeral `dev` and `prod` environments. Those constraints and their consequences are recorded transparently in the [architecture decision records](docs/adr/README.md) and [disaster-recovery strategy](docs/disaster-recovery/strategy.md).

For implementation detail, see the [architecture diagrams](docs/diagrams/README.md), including network, request, data, and security flows.

## Evidence

| Outcome | Verified result | Detail |
|---|---|---|
| Real incident response | An RDS password rotation caused a service outage; the application, alerting, and verification path were corrected and then force-tested. | [SEV1 incident review](docs/incidents/2026-09-30-db-password-rotation.md) |
| Instance resilience | Replacing one instance caused 3 HTTP 503s; testing with two instances produced 0 failed requests during replacement. | [E1: instance failure](docs/experiments/01-instance-failure.md) |
| Cache resilience | Two Redis reboot runs completed with 0 failed requests; p95 latency was 763 ms and 677 ms. | [E2: cache failure](docs/experiments/02-cache-failure.md) |
| Load and scaling | The test generator delivered 224.11 req/s at p95 51.09 ms with 0 errors; the application saturation point was not reached. | [E3: load and scaling](docs/experiments/03-load-and-scaling.md) |
| Deployment safety | A rolling refresh completed in 344 seconds with 0 failed requests during the k6 gate. | [E4: rolling deploy](docs/experiments/04-rolling-deploy.md) |
| Recovery | Point-in-time recovery took 1,141 seconds; a rebuild from teardown reached healthy service in about 31 minutes. | [E5: database restore](docs/experiments/05-database-restore.md), [E6: full rebuild](docs/experiments/06-full-rebuild.md) |

Results include their limits. For example, the load result is generator-bounded rather than a claim of application saturation, and the full teardown-to-ready wall-clock duration was not captured. The reports retain those qualifications rather than turning measurements into marketing claims.

## Engineering highlights

- **Keyless CI/CD:** GitHub Actions exchanges its identity for short-lived AWS credentials through OIDC; no cloud credentials are stored in the repository.
- **Defense in depth:** regional WAF, private application and data tiers, least-privilege IAM, SSM-only host access, IMDSv2, encryption at rest and in transit, CloudTrail, VPC Flow Logs, and IAM Access Analyzer.
- **Operationally tested:** alarms are paired with runbooks; the synthetic canary detects deep dependency failures that an ALB health check cannot see.
- **Reproducible infrastructure:** modules are tested with `terraform test`, policy checks run in CI, and drift is checked daily.
- **Intentional recovery boundary:** final RDS snapshots and point-in-time recovery preserve relational data; the documented lifecycle intentionally does not preserve ephemeral S3 artifacts and logs.

## Repository guide

| Start here | What it shows |
|---|---|
| [Architecture diagrams](docs/diagrams/README.md) | The deployed topology and network, traffic, data, and security paths |
| [Incident review](docs/incidents/2026-09-30-db-password-rotation.md) | Diagnosis, remediation, and forced-rotation validation of a real outage |
| [Resilience experiments](docs/experiments/README.md) | Measured fault injection, deployments, scaling, and recovery |
| [Security review](docs/security/README.md) | Threat model, Well-Architected findings, encryption, data handling, IAM, and incident response |
| [Observability and runbooks](docs/observability/README.md) | SLOs, alarms, dashboards, and operational procedures |
| [Disaster recovery](docs/disaster-recovery/README.md) | Recovery objectives, restoration drills, and lifecycle controls |
| [Architecture decision records](docs/adr/README.md) | Trade-offs and decisions made as the platform evolved |
| [Terraform environments](terraform/environments/) | Environment composition and configuration |
| [Go API](app/README.md) | The service deployed by the platform |

## Technology

Terraform · AWS · GitHub Actions · OIDC · Go · PostgreSQL · Redis · S3 · CloudWatch · AWS WAF · k6 · Checkov

## License

Released under the [MIT License](LICENSE).
