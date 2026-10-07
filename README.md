# CloudForge

CloudForge is a production-style AWS platform engineered with Terraform. It focuses on the work behind dependable delivery: secure infrastructure, CI/CD, observability, resilience testing, disaster recovery, and learning from production failure—not just provisioning a demo API.

[![Terraform](https://github.com/Mouad852/cloudforge/actions/workflows/terraform.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/terraform.yml)
[![Application](https://github.com/Mouad852/cloudforge/actions/workflows/app.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/app.yml)
[![Drift detection](https://github.com/Mouad852/cloudforge/actions/workflows/drift.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/drift.yml)

## Architecture

![CloudForge high-level AWS architecture](docs/diagrams/assets/architecture-high-level-generated-v2.png)

Internet traffic passes through AWS WAF to an Application Load Balancer and Auto Scaling Group in a two-AZ VPC. The Go service uses RDS PostgreSQL, ElastiCache Redis, private S3 buckets, Secrets Manager, and Route 53 private DNS; CloudWatch provides the operational signal. Terraform provisions the platform and GitHub Actions uses AWS OIDC for delivery.

## Engineering results

CloudForge was deployed, measured, intentionally broken, recovered, and improved. Results below are linked to the underlying evidence rather than presented as unqualified capacity claims.

| Exercise | Verified result | Important qualification |
|---|---|---|
| [Load test](docs/experiments/03-load-and-scaling.md) | **224.11 delivered req/s**, **51.09 ms p95**, **0 failed requests** (268,940) | The k6 generator reached its limit; application saturation and scale-out timing were not measured. |
| [Rolling deployment](docs/experiments/04-rolling-deploy.md) | **0 failed requests** in 2,179 requests during a **344 s** instance refresh | The gate measured failures; p95 was 664.13 ms during the sample. |
| [Redis reboot](docs/experiments/02-cache-failure.md) | **0 failed requests** in each of two runs | Cache recovery increased latency; the app served through its PostgreSQL fallback. |
| [Instance replacement](docs/experiments/01-instance-failure.md) | **0 failed requests** with two instances during replacement | The normal one-instance configuration did produce 3 HTTP 503s. |
| [Point-in-time recovery](docs/experiments/05-database-restore.md) | RDS restore ready in **1,141 s (19m01s)** | The successful drill measured an RPO of 286 s (4m46s). |
| [Environment rebuild](docs/experiments/06-full-rebuild.md) | Measured `prod-up` phase: **about 31m12s** | Full teardown-to-ready time was not captured; only the rebuild phase is timed. |

## What makes CloudForge different

- **Modular infrastructure as code:** Terraform modules compose networking, edge, compute, data, storage, observability, and CI/CD.
- **Keyless delivery:** GitHub Actions exchanges its identity for short-lived AWS credentials through OIDC; cloud credentials are not stored in the repository.
- **Security designed into the platform:** WAF, private application/data tiers, least-privilege IAM, SSM-only access, IMDSv2, encryption, CloudTrail, VPC Flow Logs, and Access Analyzer.
- **Operations with a feedback loop:** SLOs, CloudWatch alarms, dashboards, a deep synthetic canary, and linked runbooks turn signals into actions.
- **Failure evidence, not just design claims:** fault injection covers instance replacement and Redis failure alongside deployment and recovery drills.
- **Lifecycle-aware engineering:** daily drift detection and deliberately ephemeral environments are paired with documented data-recovery boundaries.

## Real incident → diagnosis → remediation

An RDS/Secrets Manager password rotation caused a production outage because the application cached credentials at startup. Health checks stayed green and the existing monitoring did not detect the dependency failure correctly. Operational evidence—canary history, secret rotation time, ALB access logs, and application logs—led to the diagnosis.

The fix refreshes credentials for new database connections, logs the cause behind 5xx responses, adds a canary-failure alarm and runbook, and was verified by deliberately forcing another secret rotation. Read the full [SEV1 incident review](docs/incidents/2026-09-30-db-password-rotation.md) for the timeline, impact, remediation, and validation.

## Current operating boundaries

CloudForge makes its budget and recovery trade-offs explicit: one application instance and Single-AZ RDS at rest, with scale-out capability; a NAT instance; and ephemeral environments. The load test did not establish application saturation, blue/green cutover was not measured, and cross-region recovery is not implemented or tested. These limits are part of the evidence, not hidden behind the results.

## Technology

AWS · Terraform · GitHub Actions · OIDC · Go · PostgreSQL · Redis · S3 · CloudWatch · AWS WAF · k6 · Checkov

## Explore the engineering evidence

### [Architecture](docs/diagrams/architecture-high-level.md)

See the deployed topology, then follow the network, traffic, data, and security views.

### [Engineering experiments](docs/experiments/README.md)

Review measured load, fault-injection, deployment, database-recovery, and environment-rebuild exercises.

### [Production incident](docs/incidents/2026-09-30-db-password-rotation.md)

See a real outage investigated, remediated, and deliberately re-tested.

For engineers and interviewers, the [deep technical documentation](docs/README.md) includes ADRs · Security · Observability · Runbooks · Disaster Recovery · Terraform implementation details.

## License

Released under the [MIT License](LICENSE).
