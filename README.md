# CloudForge

[![Terraform](https://github.com/Mouad852/cloudforge/actions/workflows/terraform.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/terraform.yml)
[![Application](https://github.com/Mouad852/cloudforge/actions/workflows/app.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/app.yml)
[![Drift detection](https://github.com/Mouad852/cloudforge/actions/workflows/drift.yml/badge.svg)](https://github.com/Mouad852/cloudforge/actions/workflows/drift.yml)

CloudForge is a production-style AWS platform, built with Terraform around a small Go API. It is an AWS Solutions Architect Associate (SAA-C03) graduation project and a cloud-engineering portfolio: it demonstrates the work that makes infrastructure operationally credible—security boundaries, deployment automation, observability, failure testing, recovery drills, and explicit cost/reliability trade-offs.

> **Project scope:** CloudForge is a cost-conscious, single-account learning workload in `eu-west-3`, not a claim of enterprise-grade high availability. Its environments are intentionally ephemeral; the production-shaped environment normally runs a single app instance, Single-AZ RDS, and a single Redis node.

## Contents

- [Project overview](#project-overview)
- [Architecture overview](#architecture-overview)
- [AWS services and infrastructure](#aws-services-and-infrastructure)
- [Architecture decisions and trade-offs](#architecture-decisions-and-trade-offs)
- [Infrastructure as code](#infrastructure-as-code)
- [CI/CD and deployments](#cicd-and-deployments)
- [Security architecture](#security-architecture)
- [Monitoring and observability](#monitoring-and-observability)
- [Disaster recovery and resilience](#disaster-recovery-and-resilience)
- [Testing and validated results](#testing-and-validated-results)
- [Cost optimization](#cost-optimization)
- [Deployment and reproduction](#deployment-and-reproduction)
- [Operations reference](#operations-reference)
- [Limitations and future improvements](#limitations-and-future-improvements)
- [Conclusion](#conclusion)

## Project overview

CloudForge solves a practical architecture problem: how to run and evolve a small web service in AWS with repeatable infrastructure, meaningful operational controls, and a controlled cloud bill. The application is deliberately small—a CRUD API for products and product images—so the repository can focus on the platform around it.

| Objective | Demonstrated outcome |
|---|---|
| Build a tiered AWS workload | Two-AZ VPC, public edge, private application tier, and private data tier are provisioned by Terraform. |
| Deliver without static cloud credentials | GitHub Actions uses GitHub OIDC and short-lived AWS credentials. |
| Make operational behavior observable | CloudWatch dashboards, alarms, SNS, Synthetics, logs, runbook procedures, and daily drift checks are implemented. |
| Test rather than assume resilience | Instance, cache, deployment, load, point-in-time recovery, and rebuild exercises have recorded outcomes. |
| Keep experimentation affordable | Ephemeral environments, a NAT instance, single-node data services, and planned teardown make cost a first-class design input. |

**Core technologies:** AWS VPC, EC2 Auto Scaling, Application Load Balancer, WAF, RDS for PostgreSQL, ElastiCache for Redis, S3, Route 53 private DNS, Secrets Manager, CloudWatch, SNS, CloudTrail, IAM, Terraform, GitHub Actions, Go, and k6.

## Architecture overview

<p align="center">
  <img src="docs/diagrams/assets/architecture-high-level-generated-v2.png" alt="CloudForge as-built AWS architecture" width="100%">
</p>

The architecture is deployed in **AWS `eu-west-3`** and uses the first two available Availability Zones. Each environment has six `/24` subnets inside a `/16` VPC: public, application, and data subnets in each AZ. The ALB spans both public subnets; the application ASGs span both private app subnets. RDS and Redis use subnet groups covering both data subnets, although the current data-service configuration is single-AZ/single-node.

### Request and data flow

1. A client reaches the internet-facing HTTP Application Load Balancer on port 80.
2. A regional AWS WAF web ACL evaluates managed rules, SQL injection protection, IP reputation, and a per-IP rate limit before the ALB forwards allowed traffic.
3. The listener's default weighted action sends traffic to the blue target group (`100`) and green target group (`0`) by default. The blue ASG serves the workload; the green ASG is normally at zero capacity.
4. Private EC2 instances run the Go API. They access PostgreSQL and Redis only through security-group-to-security-group rules, and use private names `db.cloudforge.internal` and `cache.cloudforge.internal`.
5. Product reads use cache-aside Redis with PostgreSQL as the source of record. Redis errors fail open to PostgreSQL. Product images are read and written by the API to a private S3 bucket; clients do not receive direct S3 access.
6. Instances fetch the RDS managed secret and Redis AUTH token from Secrets Manager, publish structured logs to CloudWatch, and use the S3 gateway endpoint for S3 traffic. Other HTTPS AWS API traffic exits through the NAT instance.

<details>
<summary><strong>Additional as-built views</strong></summary>

<p align="center">
  <img src="docs/diagrams/assets/traffic-flow-generated.png" alt="Traffic flow through WAF, ALB and Auto Scaling groups" width="100%">
</p>

<p align="center">
  <img src="docs/diagrams/assets/data-flow-generated.png" alt="Cache-aside and S3 data flow" width="100%">
</p>

The WAF body-size policy permits uploads only on `POST /api/products/{id}/image`; other oversized request bodies remain blocked. The application enforces a 5 MiB image limit. Cache entries use a 60-second TTL and are invalidated when product or image data changes.

</details>

## AWS services and infrastructure

| Service / component | Role in CloudForge | As-built details |
|---|---|---|
| VPC, subnets, route tables | Network isolation | `/16` VPC with two public, two app, and two data subnets; VPC Flow Logs capture all traffic to CloudWatch. |
| Internet Gateway and NAT instance | Public ingress and private egress | Public subnets route through the IGW. Private app/data subnets use one hardened NAT instance with an Elastic IP; an S3 gateway endpoint avoids NAT for S3 traffic. |
| EC2 and Auto Scaling | Application runtime | Amazon Linux 2023 ARM64/Graviton launch template; no public IPs; IMDSv2 required; encrypted EBS; blue and optional green ASGs. CPU target tracking exists for blue. |
| ALB and target groups | Public service edge and routing | Internet-facing ALB in two AZs, HTTP listener, shallow `/healthz` health checks, access logs to private S3, weighted blue/green forwarding. |
| AWS WAF | Layer-7 filtering | Regional ACL attached directly to the ALB: Common, Known Bad Inputs, IP Reputation, 2,000 requests/5 minutes/IP, SQLi, and path-aware body-size rules. |
| RDS PostgreSQL | System of record | PostgreSQL 16 in private data subnets; encrypted storage, TLS forced, Secrets Manager managed master password, CloudWatch PostgreSQL logs, Performance Insights, backups, final snapshots, and private DNS. |
| ElastiCache Redis | Cache-aside acceleration | One encrypted Redis node with TLS and AUTH token from Secrets Manager. It is not an HA cache and does not have automatic failover. |
| S3 | Artifacts, images, and ALB/canary evidence | Separate versioned artifact and image buckets plus ALB log buckets. Public access is blocked and TLS-only bucket policies are enforced. Product images are deliberately private. |
| Route 53 private hosted zone | Internal discovery | Per-VPC `cloudforge.internal` zone supplies stable DB and cache names without exposing AWS-generated endpoints to application configuration. |
| Secrets Manager | Runtime credentials | RDS-managed master credential and Terraform-generated Redis token. The application refreshes the RDS password for each new DB connection; Redis token rotation is **not automated**. |
| CloudWatch and SNS | Signals and notifications | Golden Signals/SLO dashboards, metrics, logs, alarms, composite alarm, Synthetics canary every five minutes, and email SNS topics. Billing notifications use `us-east-1` because AWS billing metrics live there. |
| CloudTrail and IAM Access Analyzer | Audit and exposure visibility | Multi-Region management-event CloudTrail with log-file validation; account-level Access Analyzer is configured. |
| IAM and GitHub Actions OIDC | Workload and delivery identity | Least-privilege workload roles; separate plan and apply OIDC roles; SSM Session Manager replaces SSH. |

### The application

The Go service provides `GET/POST/DELETE /api/products`, product-image upload/download, `/healthz`, `/readyz`, and `/whoami`. Migrations are embedded in the binary and run under a PostgreSQL advisory lock at startup. `/healthz` is intentionally shallow so a dependency outage does not remove all instances from the ALB; `/readyz` pings PostgreSQL and Redis and is used by the deployment gate and synthetic monitoring.

## Architecture decisions and trade-offs

The repository intentionally chooses practical learning value and bounded spend over maximum availability. The most important decisions are below; historical CloudFront-based designs were superseded after CloudFront access was permanently denied, so the current public edge is the WAF-protected ALB.

| Decision | Rationale and implementation | Trade-off / boundary |
|---|---|---|
| NAT instance, not NAT Gateway | One AL2023 NAT instance provides private-subnet egress; source/destination checks are disabled and iptables masquerading is configured. | Lower recurring cost, but one egress point is a single point of failure and needs instance maintenance. |
| Single-AZ/single-node data services at rest | Normal operating settings are one app instance, Single-AZ RDS, and one Redis node. | Lower cost; EC2 replacement and cache recovery are tested, but no automatic RDS AZ failover or Redis failover exists. |
| Ephemeral dev and production-shaped environments | `dev-down`, nightly dev teardown, and guarded `prod-down` remove runtime resources; final RDS snapshots preserve relational data. | S3 images, artifacts, canary output, and ALB logs are intentionally outside the planned-teardown recovery boundary. |
| Rolling deployment is the implemented default | `scripts/deploy.sh` uploads an ARM64 binary, creates a launch-template version, launches an ASG instance refresh at 100% minimum healthy capacity, and runs a k6 failure gate. | Verified under load; rollback is an operator action, not automatic traffic rollback. |
| Blue/green is provisioned as a second strategy | Two target groups, a green ASG, and Terraform-configurable listener weights exist. Default is blue/green `100/0`; green is normally zero. | The weighted path is implemented, but an end-to-end blue/green cutover has **not** been measured and no workflow automates it. |
| Private tiers and SSM-only access | EC2 has no public IP/SSH/key pair; app-to-data traffic is security-group scoped; SSM is used for administration. | The ALB is intentionally open on HTTP because it is the public edge; viewer TLS is not implemented. |
| Native RDS backup and restore | Automated backups, point-in-time recovery, final snapshots, and a scripted integrity drill are used instead of AWS Backup or standby infrastructure. | No cross-Region copy, warm standby, active-active service, or automatic restore test. |
| Cost-aware AWS defaults | Graviton where capacity permits, S3 lifecycle rules, log retention, budgets, and teardown automation reduce experiment cost. | This is not a capacity or availability optimisation for a persistent production service. |

## Infrastructure as code

Terraform `>= 1.11` and the AWS provider `~> 5.0` describe the platform. The design separates account bootstrap from environment state and composes each environment from modules.

```text
terraform/
├── bootstrap/                 # remote-state bucket, budget, CloudTrail, OIDC, Access Analyzer
├── environments/
│   ├── dev/                   # isolated dev state and composition
│   └── prod/                  # isolated production-shaped state and composition
└── modules/
    ├── network/               # VPC, subnets, NAT, routes, Flow Logs, private DNS
    ├── edge/                  # ALB, target groups, WAF, access-log bucket
    ├── compute/               # IAM, launch template, ASGs, scaling
    ├── database/              # RDS, parameter/subnet groups, private DNS
    ├── cache/                 # Redis, secret, subnet group, private DNS
    ├── storage/               # artifacts and private product-image buckets
    ├── observability/         # dashboards, alarms, canary, SNS
    └── cicd-oidc/             # GitHub OIDC provider and roles
```

### State, configuration, and dependencies

- Bootstrap creates a versioned, AES256-encrypted, public-blocked S3 state bucket. Environment backends use separate state keys and S3 lock files.
- `terraform.tfvars.example` files are the safe starting point for each environment. They configure capacity, retention, database protection, and notification email; do not commit real `terraform.tfvars` values or credentials.
- The environment root wires module outputs to dependents (for example, network to edge/compute/data, then observability). Terraform resource references express the deployment order; no shell orchestration is required for normal dependencies.
- The repository includes native Terraform tests. CI runs read-only tests for cache, OIDC, compute, database, edge, observability, and storage; the network test is run on trusted non-PR triggers because it applies a real test instance.

### Verified infrastructure commands

```bash
# Bootstrap once with an authenticated AWS CLI profile, after reviewing variables.
cd terraform/bootstrap
terraform init
terraform apply

# Initialise and provision an environment.
cd ../environments/dev
terraform init
terraform plan
terraform apply
```

Use `make dev-up`, `make dev-down`, `make prod-up`, and the guarded `make CONFIRM_PROD_DOWN=YES prod-down` from the repository root for lifecycle-aware workflows. `prod-up` restores only from the newest available final RDS snapshot; it refuses to create an empty production-shaped database.

## CI/CD and deployments

### GitHub Actions

| Workflow | Trigger and implemented actions |
|---|---|
| `terraform.yml` | On Terraform/policy PRs: formatting, TFLint, Checkov including custom checks, Terraform plan comments, Infracost PR comments, and module tests. On `main` or manual dispatch: gated dev apply then prod apply, artifact bootstrap if needed, and lifecycle-state recording. |
| `app.yml` | Tests, `go vet`, and `govulncheck` for application changes. On `main`, deploys dev using OIDC, then runs the rolling refresh plus k6 gate. |
| `drift.yml` | Daily and manual drift checks for dev/prod. Opens or updates a GitHub issue and sends an SNS notification when Terraform finds drift. An intentional teardown is skipped only when its GitHub lifecycle variable says `down` **and** state is empty. |
| `nightly-destroy.yml` | Daily dev teardown with a state-empty verification and lifecycle-state update. It removes orphaned Synthetics log groups created by AWS. |

### OIDC identity model

GitHub Actions does not store an AWS access key. GitHub issues a short-lived OIDC token and AWS STS exchanges it for role credentials. Trust policies check `aud = sts.amazonaws.com` and GitHub's immutable repository subject claim. The `terraform-plan` role is read-only with narrow exceptions for alert publishing and required secret reads; the `terraform-apply` role is used only by trusted main/environment jobs and has PowerUserAccess plus IAM actions scoped to project-prefixed roles and instance profiles.

This is deliberately not described as perfect least privilege: a compromised approved apply job is still a major account risk. Branch protection and GitHub environment approval are essential compensating controls.

### Rolling deployment and blue/green status

The implemented deployment command is:

```bash
K6_DURATION=8m bash scripts/deploy.sh prod
```

It builds `linux/arm64` with CGO disabled, uploads the binary to the Terraform output artifact location, creates a launch-template version, starts an ASG instance refresh (`MinHealthyPercentage: 100`, `MaxHealthyPercentage: 200`), and concurrently sends k6 traffic to `/readyz`. Any failed request fails the deployment script; a failed/cancelled instance refresh also stops it.

The ALB listener supports weighted blue/green forwarding through `blue_weight` and `green_weight`. Terraform provisions the green fleet and target group, but traffic shifting, validation, and rollback are currently manual Terraform operations. The current default remains blue `100`, green `0`.

## Security architecture

<p align="center">
  <img src="docs/diagrams/assets/security-request-path-generated.png" alt="CloudForge request security boundaries" width="100%">
</p>

### Implemented controls

| Area | Controls in the repository |
|---|---|
| Network | Internet access ends at the ALB. Instances have no public IPs. The app SG accepts only the ALB SG; RDS and Redis accept only the app SG. Default VPC SG is locked down. |
| Edge protection | WAF managed Common, Known Bad Inputs, IP Reputation, and SQLi rules; per-IP rate limiting; body-size handling; invalid ALB headers are dropped. AWS Shield Standard applies automatically. |
| Data protection | RDS storage, Redis at rest, EBS, and S3 use encryption at rest. RDS forces TLS; Redis uses TLS plus AUTH; bucket policies deny insecure transport and public access blocks are enabled. |
| Secrets | RDS master password is managed by Secrets Manager; Redis AUTH is stored there. The app reads the current DB password when creating each connection, fixing the password-rotation outage described below. |
| Identity | App role is scoped to artifacts, images, required secrets, its log group, SSM, and a constrained custom-metric namespace. Canary, NAT, and Flow Logs use distinct roles. |
| Administration | SSM Session Manager is the only host access path; no SSH ingress, bastion, or EC2 key pair is provisioned. IMDSv2 is mandatory. |
| Delivery and audit | OIDC replaces static CI credentials. CloudTrail records multi-Region management events with log-file validation; Access Analyzer watches for external sharing. |
| Guardrails | Terraform CI runs formatting, TFLint, Checkov and custom checks. Pre-commit configuration includes secret scanning; daily drift detection reports unmanaged changes. |

### Security boundaries and known gaps

CloudForge is direct about the limits of its security posture. It has **no end-user authentication or authorization**, because the API is a demo. The ALB is HTTP-only; client-to-ALB and ALB-to-instance traffic is not TLS-protected. The app has unrestricted HTTPS egress, runs as root in its systemd unit, and artifact execution does not verify a checksum/signature. WAF helps with common attacks but is not a distributed-DDoS or bot-control solution. GuardDuty, Security Hub, Inspector, multi-account isolation, customer-managed KMS keys, and automated Redis token rotation are not implemented.

These are documented constraints, not capabilities implied by the project.

### Verified security behavior

- SQL injection test payloads that previously passed were re-tested and blocked with HTTP 403 by the WAF SQLi rule on both environments.
- A 20 KB image upload succeeds, while a 20 KB JSON body to the product API is blocked; the WAF exception is limited to the image-upload path.
- Public ALB requests were verified, direct S3 object reads are denied by design, and images are served through the application.
- A Well-Architected review recorded six remediated high-risk findings, moving the documented total from 22 to 16. Remaining risks are intentionally tracked as constraints or future work.

## Monitoring and observability

CloudWatch provides a Golden Signals dashboard, SLO dashboard, application and PostgreSQL log groups, VPC Flow Logs, ALB metrics, RDS/Redis metrics, WAF metrics, and a Synthetics canary. The canary calls the public ALB path every five minutes and writes artifacts beneath its own S3 prefix. Regional alarms publish to an SNS email topic; billing alarms use an SNS topic in `us-east-1`.

| Signal | Purpose |
|---|---|
| ALB unhealthy hosts, target 5xx, p95 latency | Detect edge/target availability, errors, and latency. |
| ASG in-service instances and EC2 CPU | Detect lost capacity and scaling pressure. |
| RDS CPU, free storage, and connections | Detect database stress/capacity pressure. |
| Redis memory and evictions | Detect cache capacity and behavior changes. |
| Synthetics canary failure | Detect end-to-end API availability from outside the app. |
| Composite `service-degraded` alarm | Aggregate materially degraded service signals. |
| Budget and billing | Detect cost pressure; the budget measures pre-credit cost because CloudWatch estimated charges may stay zero while AWS credits apply. |

### SLO baseline and incident learning

The 30-day rolling objectives are availability **99.5%**, latency **99% of requests p99 < 500 ms**, and correctness **99.9% non-5xx**. These are external measurements: the Synthetics canary and ALB metrics, not the app's self-reporting.

On 2026-09-30, RDS password rotation exposed a defect: the application had cached the database password at startup. As old connections expired, database-backed requests failed for roughly 40 hours while shallow ALB health checks stayed healthy. The incident exhausted the availability error budget. Investigation used canary history, secret rotation timing, ALB logs, and app logs. The remediation refreshes the secret for every new PostgreSQL connection, records the cause of 5xx responses, adds the canary-failure alarm/runbook, and was verified with a forced secret rotation.

This is also an important qualification: observed availability during 2026-09-29 through 2026-10-06 was **78.26%** (1,746 successful / 2,231 canary samples), dominated by that incident. The project does not present its SLO target as achieved during that window.

<details>
<summary><strong>Operational response model</strong></summary>

Alarm procedures cover ALB 5xx/latency/unhealthy targets, ASG capacity, EC2 CPU, RDS CPU/free storage/connections, Redis memory/evictions, canary failures, service degradation, billing, deployment failure, load-test windows, lifecycle state, and full account cleanup. The common response is: capture ephemeral evidence first, triage severity, contain the impact, investigate with CloudTrail/logs/metrics, recover through verified health checks, then record the lesson.

For a suspected compromise, place the instance in ASG standby before terminating it, snapshot its root volume, capture process/network information through SSM, inspect role activity in CloudTrail and relevant Flow Logs, then replace it after preserving evidence. For a credential leak, deactivate/rotate credentials, inspect CloudTrail, investigate unrecognised regional resources, run Terraform plans/drift checks, and monitor the pre-credit budget.

</details>

## Disaster recovery and resilience

CloudForge uses **backup and restore** in `eu-west-3`, not standby or multi-Region disaster recovery. RDS has automated backups (one-day retention on the credit-bounded configuration), point-in-time recovery, manual snapshots, and a final snapshot on Terraform destroy. A final snapshot protects PostgreSQL rows only; planned teardown deliberately destroys S3 images, artifacts, canary output, and ALB access logs.

<p align="center">
  <img src="docs/diagrams/assets/disaster-recovery-flow-generated.png" alt="CloudForge disaster recovery flow" width="100%">
</p>

### Recovery model

| Scenario | Target set before drill | Observed / current status |
|---|---:|---|
| Unplanned DB loss | RPO ≤ 15 minutes | Successful point-in-time drill measured 286 seconds (4m46s). |
| Point-in-time restore | RTO ≤ 60 minutes | Temporary database became ready in 1,141 seconds (19m01s); marker was found and row count verified. |
| Planned teardown—PostgreSQL | RPO = 0 | Final snapshot restored successfully; application health checks passed. |
| Full environment rebuild | RTO ≤ 45 minutes | Measured `prod-up` phase was about 31m12s. Full teardown-to-ready duration was not captured. |
| Planned teardown—S3/logs | No recovery target | Intentionally unrecoverable by this path. New artifacts are rebuilt and uploaded. |

`make restore-test RESTORE_ENV=prod` is a manual, destructive-cost integrity drill. It writes a marker, waits until it is restorable, restores a temporary database, verifies the marker and product count through SSM, records fallback/capacity attempts outside the worktree, and deletes the temporary database. The successful drill required an instance-class fallback from unavailable `db.t4g.micro` capacity to `db.t3.micro`; capacity is therefore an explicit RTO risk.

`make CONFIRM_PROD_DOWN=YES prod-down` disables required deletion protection, destroys the environment after a final snapshot, verifies empty state, and records lifecycle state. `make prod-up` finds the newest final snapshot, recovers/imports a Redis secret if it is in its recovery window, applies Terraform, ensures an app artifact exists, and records the environment as up.

### Resilience boundaries

- The NAT instance is a single private-egress failure point.
- The normal one-instance configuration can produce a brief user-visible outage during instance replacement.
- Redis has one node; the application continues by querying PostgreSQL, but latency increases.
- There is no tested AZ impairment, Multi-AZ failover, cross-Region backup copy, warm standby, active-active topology, or automated restore schedule.

## Testing and validated results

The following results are measured exercises, not extrapolated capacity promises. Evidence files for several k6/restore exercises were intentionally kept outside the repository to avoid committing sensitive endpoint/operator information; reported numbers identify their source, method, and qualification.

| Exercise | Measured result | Interpretation |
|---|---|---|
| E1: instance termination | At one instance, 3 HTTP 503s / 269 requests (1.115%); at two instances, 0 / 314 failures. | ASG replacement is fast but not invisible at one-instance capacity. Two instances prevented failures in this sample but had a short latency spike. |
| E2: Redis reboot | Two runs recorded 0 failures: 167 and 659 requests. Redis became available 93.65 seconds after the first reboot request. | Cache-aside fallback preserved HTTP availability; latency rose (full-run p95 677.23 ms, max 6.45 s). |
| E3: load ramp | 224.11 delivered requests/s, p95 51.09 ms, 0 failed of 268,940. | Lower bound only. At a 400 req/s target k6 reached 500 VUs and dropped 609 iterations; generator/runtime—not the app—was limiting. No scale-out timing was measured. |
| E4: rolling deployment | 0 failed of 2,179 requests during a 344-second instance refresh. | The rolling deployment failure gate passed. p95 was 664.13 ms, so zero failures must not be read as zero latency impact. |
| E5: point-in-time RDS recovery | RPO 286 s; restore-ready 1,141 s; marker verified. | One successful integrity-checked drill met its target after capacity fallback; repeatability is not yet established. |
| E6: full rebuild | `prod-up` about 31m12s; `/readyz` and `/api/products` returned 200. | Planned database recovery worked from the final snapshot. The complete teardown-to-ready duration was not captured, and S3 data was intentionally absent. |

<p align="center">
  <img src="docs/screenshots/14-portfolio/e1-instance-failure-comparison.png" alt="Instance-failure comparison" width="48%">
  <img src="docs/screenshots/14-portfolio/e2-e4-latency-summary.png" alt="Cache and deployment latency summary" width="48%">
</p>

<p align="center">
  <img src="docs/screenshots/14-portfolio/e5-e6-recovery-timings.png" alt="Recovery timing summary" width="65%">
</p>

### Validation implemented in the repository

- Go unit/integration tests, `go vet`, and `govulncheck` run in CI; local `make -C app test` runs the application test suite.
- Terraform CI runs `terraform fmt -check`, TFLint, Checkov plus project custom policies, plans, Infracost PR comments, and native module tests.
- The WAF benchmark helper adds only the generator IP to a dedicated rate-limit exemption list for a bounded window, validates cleanup, and the daily drift workflow reports a leftover exemption.
- The delivery script gates rolling refresh on a zero-failed-request k6 run. It does not measure or automatically enforce latency.

## Cost optimization

CloudForge treats cloud cost as an architecture constraint rather than an afterthought:

- Dev is automatically destroyed nightly; both environments can be intentionally torn down and rebuilt from configuration/snapshot.
- One NAT instance replaces a managed NAT Gateway, accepting an egress availability/maintenance trade-off.
- Default runtime settings favour one app instance, Single-AZ RDS, one Redis node, small Graviton-capable instance families, bounded log retention, and no always-on standby stack.
- S3 lifecycle rules expire superseded artifact versions, canary reports, and access logs; final snapshots preserve database rows through teardown.
- Cost allocation tags, an AWS Budget measured before credits, billing alarms, and Infracost PR comments provide budget visibility.

### Measured cost evidence (not a bill forecast)

Cost Explorer measured **$113.26 before credits** during September 2026. For 2026-10-01 through 2026-10-05, the production-shaped environment averaged **$2.9308/day** (derived **$0.1221/hour**) before credits; AWS marked daily values as estimated. The largest tagged service totals in the 2026-09-30 through 2026-10-06 window included ALB ($3.9697), RDS ($2.8699), ElastiCache ($2.7000), CloudWatch ($2.5050), and WAF ($2.0387).

No three-day post-teardown resting-cost window was observed, so CloudForge does **not** claim teardown makes cost zero. Snapshots, state, retained logs, and bootstrap/untagged resources can still incur cost.

## Deployment and reproduction

### Prerequisites

- AWS account with permissions to bootstrap the resources, plus AWS CLI authentication configured for `eu-west-3`.
- Terraform `>= 1.11`, GNU Make, Bash, Git, and the GitHub CLI (`gh`) for lifecycle-state updates.
- Go version specified in `app/go.mod`; Docker Desktop/Compose for local app dependencies.
- A confirmed email address for SNS notifications.
- For CI: GitHub environments/approvals, repository variables `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, and `ALERT_EMAIL`; `INFRACOST_API_KEY` secret for Infracost comments.

Never commit access keys, backend identifiers from a private account, real `terraform.tfvars`, generated state, endpoints, or secret values. Start from the committed `terraform.tfvars.example` files and set a real alert email locally or through CI variables.

### 1. Run the API locally

```bash
cd app
make dev-up

# In a second shell; migrations run automatically when the app starts.
DATABASE_URL="postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable" \
REDIS_ADDR=localhost:6379 \
S3_ENDPOINT=http://localhost:4566 \
S3_BUCKET=cloudforge-images-dev \
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
go run .

# Optional test command (requires the local dependencies above).
make test
```

Use `make dev-down` inside `app/` to remove local Docker volumes and containers.

### 2. Bootstrap shared AWS foundations

Review `terraform/bootstrap/terraform.tfvars`, then initialise and apply bootstrap. It creates/imports account-level foundations including state, OIDC roles, CloudTrail configuration, the budget, and Access Analyzer. Copy its role outputs into the GitHub repository variables named above before enabling Actions.

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

### 3. Provision an environment

Create a local `terraform.tfvars` from the appropriate example, set only safe local values such as `alert_email`, then apply:

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

For the repository's lifecycle-aware developer path from the root, run:

```bash
make dev-up
```

This restores from the latest final dev snapshot when one exists, otherwise creates a fresh database, ensures the app artifact is present, and records expected lifecycle state in GitHub.

### 4. Deploy and verify

After Terraform has produced outputs and AWS CLI credentials have the required permissions:

```bash
# From repository root; defaults to dev when no environment is supplied.
bash scripts/deploy.sh dev

# Read the public ALB DNS name from Terraform, then verify shallow/deep checks.
terraform -chdir=terraform/environments/dev output -raw alb_dns_name
curl http://<alb-dns-name>/healthz
curl http://<alb-dns-name>/readyz
curl http://<alb-dns-name>/api/products
```

The GitHub application workflow performs the same dev deployment path after tests on `main`. Check that the Synthetics canary is running, confirm SNS subscriptions, review dashboards, and ensure targets are healthy before treating the environment as ready.

### 5. Controlled testing and cleanup

Run capacity testing only with the WAF-window wrapper; it adds and removes a narrowly scoped exemption for the generator:

```bash
scripts/waf-benchmark-window.sh dev --max-minutes 30 -- k6 run scripts/capacity-test.js
```

Destroy dev through the lifecycle command:

```bash
make dev-down
```

Production-shaped teardown is intentionally guarded and permanently removes the environment's S3 buckets/logs while retaining a final RDS snapshot:

```bash
make CONFIRM_PROD_DOWN=YES prod-down
```

Rebuild it only from the final snapshot:

```bash
make prod-up
```

## Operations reference

### Alarm triage checklist

| Alarm class | First checks | Typical response |
|---|---|---|
| ALB 5xx or failed canary | Canary history, ALB access logs, app logs, `/readyz`, target health | Preserve evidence, identify dependency/application failure, then deploy/refresh or recover the dependency. |
| High ALB latency / EC2 CPU | Golden Signals dashboard, ASG desired/in-service capacity, recent deploys | Check saturation and scale activity; do not assume target tracking has already completed. |
| Unhealthy targets / lost ASG instance | Target health reasons, ASG activity, instance logs via SSM | Allow or trigger replacement after investigating; a one-instance fleet can cause a visible gap. |
| RDS resource alarms | Connections, CPU, storage, slow-query/PostgreSQL logs | Reduce load, investigate query/connection patterns, and protect data before changing capacity. |
| Redis memory/evictions | Cache metrics, application warning logs, hit/miss behavior | Treat Redis as a performance issue first; application reads fall back to PostgreSQL. |
| Budget / unexpected cost | Cost Explorer grouped by service and tags, all Regions, account-plan credit state | Tear down unneeded dev; investigate unfamiliar untagged resources as a possible credential incident. |
| Drift issue | Terraform plan output and lifecycle-state variable | Reconcile intentional changes in Terraform; never silence a state/lifecycle inconsistency. |

### Important manual procedures

- **Deployment rollback:** stop on a failed deploy gate; identify the prior launch-template version and start an ASG instance refresh against it after verifying the artifact/version. This is a manual recovery procedure; the script does not roll traffic back automatically.
- **RDS recovery drill:** `make restore-test RESTORE_ENV=prod` creates a temporary RDS instance and incurs cost. Confirm capacity/quota first and save output outside the repository.
- **Redis secret lifecycle:** `make prod-up` invokes the preflight that restores/imports the named Redis secret if AWS still holds it in a recovery window. Do not delete that preflight when changing teardown behavior.
- **Full account cleanup:** account-wide cleanup is intentionally a manual, cautious process because it may affect resources outside CloudForge; do not run broad cleanup scripts without reviewing the exact account/region target.

## Limitations and future improvements

The following are **not yet implemented** unless stated otherwise:

- HTTPS listener, ACM certificate, custom domain, and CloudFront/CDN. The ALB is currently HTTP-only because CloudFront access was denied and no replacement TLS path has been added.
- Application authentication/authorization, content-type validation for uploads, and antivirus/content scanning.
- Multi-AZ RDS failover in the operating configuration, Redis replication/automatic failover, a redundant NAT design, or a tested Availability Zone impairment exercise.
- Cross-Region backups/replication, warm standby, pilot light, active-active recovery, and automated recurring restore tests.
- Automated blue/green launch, health validation, traffic shifting, or rollback. The building blocks exist, but only the rolling strategy has measured deployment evidence.
- Demonstrated scale-out timing or application saturation. The recorded load test was generator-bounded.
- GuardDuty, Security Hub, Inspector, egress controls, a permissions boundary for CI-created roles, Action SHA pinning, checksum verification for the boot artifact, and process hardening to run the app as a non-root user.
- A measured post-teardown resting cost, preserving S3 data through planned teardown, or a production multi-account separation.

## Conclusion

CloudForge demonstrates practical AWS architecture rather than only resource provisioning: a segmented VPC, secure-ish workload identity and delivery, a WAF-protected application edge, modular Terraform, operational telemetry, controlled lifecycle automation, and recovery work that was actually exercised.

Most importantly, it records where the system is deliberately constrained. The documented incident, generator-bounded load test, one-instance failure result, single-region recovery boundary, and missing TLS/HA features make the portfolio evidence more useful than generic claims of production readiness. It shows the architectural judgement, automation discipline, security thinking, and operational learning expected of an AWS-focused cloud or DevOps engineer.

## License

Released under the [MIT License](LICENSE).
