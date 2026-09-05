# CloudForge — Highly Available Production Cloud Platform

**Plan version:** 2.0 — 2026-09-04
**Graduation:** June 2027 · **Build window:** ~18 weeks at 8–10 h/week
**Positioning:** Flagship #2, paired with Pitstop. Pitstop = Kubernetes / DevSecOps. CloudForge = AWS infrastructure engineering, availability, resilience, disaster recovery, SRE practice.

---

## Table of contents

| § | Section |
|---|---|
| 1 | What this project proves |
| 2 | Verdict on the original brief |
| 3 | Non-goals |
| 4 | Cost strategy |
| 5 | Target architecture |
| 6 | Architecture decisions (ADRs) |
| 7 | Repository structure |
| 8 | Milestones M0–M14 |
| 9 | The differentiators — why this beats a normal AWS portfolio project |
| 10 | SLOs, SLIs and the error budget |
| 11 | The measurements table |
| 12 | Portfolio artifacts checklist |
| 13 | Risks |
| 14 | CV output |
| 15 | Interview preparation |
| 16 | Account status |
| 17 | Decision log and open items |
| 18 | Documentation and proof of work |
| 19 | Immediate next actions |

---

## 1. What this project proves

Most AWS portfolio projects prove one thing: *"I can follow a tutorial and click through the console."* This one is designed to prove four things a hiring manager actually cares about:

1. **I can design an architecture and justify every choice.** (ADRs, Well-Architected review)
2. **I can build it reproducibly, and prove it.** (Terraform, module tests, destroy→apply timing)
3. **I know what happens when it breaks, because I broke it on purpose and measured it.** (game days, SLOs, error budget)
4. **I operate it like it costs someone money.** (cost analysis, budget guardrails, ephemeral environments)

The application is a prop. Say so plainly in the README — pretending a 400-line CRUD API is the point undermines everything else.

---

## 2. Verdict on the original brief

The concept was strong and correctly scoped. The core insight — *the infrastructure is the product* — is exactly what separates a portfolio project from a tutorial. Changes made:

| # | Brief said | Changed to | Why |
|---|-----------|-----------|-----|
| 1 | 3 environments (dev/staging/prod) | **2 environments**, staging one `.tfvars` away | 3× the bill for zero extra CV value. Module reuse is proven by two consumers. |
| 2 | CloudFront in front of ALB **and** S3 | **One distribution, two origins** | With no custom domain, the `*.cloudfront.net` default certificate is the only free path to valid HTTPS — so the ALB origin is justified rather than decorative. |
| 3 | Deploy, then screenshot | **Everything ephemeral** | Steady-state cost under $2/month, and a working destroy→apply cycle is the headline claim anyway. |
| 4 | NAT Gateway everywhere | **NAT GW in prod, NAT instance in dev** | ~$33/mo → ~$3/mo. This *is* the cost-engineering evidence. |
| 5 | *(missing)* | **How you deploy new versions** | See §2.1. The brief never answered this and every interviewer asks. |
| 6 | Spring Boot | **Go** | ~12 MB static binary, boots in milliseconds, runs on `t4g.micro`. Halves compute cost and removes JVM warm-up from every scaling measurement. |

### 2.1 The gap the brief missed: deployment

Without Kubernetes there is no `kubectl set image`. The answer:

```
git push
   │
   ▼
CI: test → build → upload binary to versioned S3 key
   │
   ▼
New Launch Template version
   │
   ▼
ASG Instance Refresh   (MinHealthyPercentage = 100, one batch at a time)
   │
   ├─► launch instance from new LT version
   ├─► wait for ALB target group = healthy
   ├─► drain connections (graceful shutdown), terminate one old instance
   └─► repeat until fleet is on the new version
```

**Zero-downtime rolling deploys with no orchestrator.** In M8 you also build blue/green as a second strategy and write up the comparison — two deployment strategies implemented and contrasted is a strong, uncommon interview answer.

---

## 3. Non-goals — protect this list

Do not add: Kubernetes, EKS, ECS, ArgoCD, Istio, Jenkins, Vault, Kafka, Prometheus/Grafana/Loki, Lambda-based microservices, a frontend, AI features, multi-region active-active.

Pitstop carries all of that. CloudForge's value is **focus**.

Test for any new idea: *"Does this produce a measurement, a security property, or an operational artifact I cannot already demonstrate?"* If no, cut it. §9 lists the additions that passed this test; everything else was rejected.

---

## 4. Cost strategy

Approximate `prod` figures, `eu-west-3`, Go on `t4g.micro` (**verify against the AWS Pricing Calculator**):

| Resource | ≈ Hourly | ≈ Monthly if left running |
|---|---|---|
| NAT Gateway (1, single-AZ) | $0.045 | ~$33 |
| Application Load Balancer | $0.025 | ~$18 |
| RDS PostgreSQL `db.t4g.micro` Multi-AZ | $0.038 | ~$28 |
| ElastiCache Redis `cache.t4g.micro` | $0.016 | ~$12 |
| 2× EC2 `t4g.micro` | $0.017 | ~$12 |
| WAF web ACL + managed rules | ~$0.010 | ~$7 |
| Secrets Manager, CloudWatch, S3, CloudFront | — | ~$5–10 |
| **Total** | **≈ $0.15 / hour** | **≈ $115–135 / month** |

> **Confirmed 2026-09-04: there is no free-tier cushion under these numbers.** This account is on the post-July-2025 model — credits instead of the legacy 12-month allowances (§17). Every EC2, RDS, EBS, ALB and NAT Gateway hour bills against a finite $158 from the first second.

### The rule: nothing runs overnight — not even dev

The number that matters is **$0.15/hour**, not $115/month.

- **Both environments ephemeral.** `make dev-up` when you sit down, `make dev-down` when you stop. At 10 h/week, dev costs **$2–4/month**. A six-hour full-HA prod game day is about **$1**.
- **Steady-state cost under $2/month**: state bucket, artifact/image buckets, retained snapshots. Everything else is code, not running resources.
- **This is a headline claim, not a compromise.** README, verbatim: *"The platform's resting cost is under $2/month, because it exists as code. A full production environment is 14 minutes and $0.15/hour away."*
- **Snapshot on down, restore on up** (ADR-015), or the workflow becomes annoying enough that you stop following it.
- **A nightly scheduled `terraform destroy` on dev** in GitHub Actions, as a backstop for the night you forget (M8).

### Guardrails — M0, non-negotiable

1. AWS Budget at $20 with alerts at 50/80/100%.
2. CloudWatch billing alarm → SNS → email.
3. **AWS Cost Anomaly Detection** (free) — catches the thing a fixed threshold misses.
4. `default_tags` on the provider: `Project`, `Environment`, `ManagedBy`, `Owner`. Cost Explorer grouped by tag produces `docs/cost-analysis.md` with real numbers.
5. `scripts/aws-inventory.sh` after every teardown.

---

## 5. Target architecture

```
                            INTERNET
                                │
                                ▼
                    ┌───────────────────────┐
                    │      CloudFront       │  free *.cloudfront.net TLS
                    │   + AWS WAF (managed  │  managed rule groups
                    │     rule groups)      │
                    └───────────┬───────────┘
                    /images/*   │   /api/*
              ┌─────────────────┴─────────────────┐
              ▼                                   ▼
      ┌──────────────┐                   ┌─────────────────┐
      │  S3 (OAC)    │                   │       ALB       │  locked to CloudFront
      │  private     │                   │  public subnets │  prefix list + secret header
      └──────────────┘                   └────────┬────────┘
                                                  │
                          ┌───────────────────────┴──────────────────────┐
                          ▼                                              ▼
                  ┌───────────────┐                              ┌───────────────┐
                  │  EC2  (ASG)   │        app subnet            │  EC2  (ASG)   │
                  │     AZ-A      │                              │     AZ-B      │
                  └───────┬───────┘                              └───────┬───────┘
                          └──────────────────────┬───────────────────────┘
                                                 │
                          ┌──────────────────────┴──────────────────────┐
                          ▼                    data subnet              ▼
                  ┌───────────────┐                            ┌───────────────┐
                  │ RDS Postgres  │                            │  ElastiCache  │
                  │   Multi-AZ    │                            │     Redis     │
                  └───────────────┘                            └───────────────┘

   OBSERVABILITY                SECURITY                      RESILIENCE
   ├ CloudWatch metrics         ├ IAM least privilege         ├ AWS Backup + vault
   ├ CloudWatch Logs            ├ Secrets Manager + rotation  ├ Cross-region snapshot copy
   ├ Alarms → SNS → email       ├ SSM Session Manager         ├ AWS FIS experiments
   ├ Synthetics canary          ├ CloudTrail (free)           ├ SSM Automation runbooks
   ├ SLO dashboard              ├ GuardDuty (trial window)    └ Automated restore testing
   └ Four Golden Signals        └ VPC Flow Logs

                              ALL OF IT: TERRAFORM
```

---

## 6. Architecture decisions (ADRs)

Write each up in `docs/adr/` **as you make it**. An ADR log is a senior-engineer signal and it is what you re-read before an interview.

| ID | Decision | Rationale | Rejected |
|---|---|---|---|
| 001 | Terraform, S3 backend, **native S3 locking** (`use_lockfile`, TF ≥ 1.11 — you have 1.15.6) | No DynamoDB table to run or pay for; current best practice | DynamoDB lock table (legacy), Terraform Cloud (hides mechanics you want to learn) |
| 002 | Separate state file per environment | Blast-radius isolation — a broken dev apply cannot corrupt prod | Workspaces (state coupling, easy to apply to the wrong one) |
| 003 | **ARM / Graviton** (`t4g`) for EC2 and RDS | ~20% cheaper at equal performance; Go cross-compiles with one env var | x86 `t3` |
| 004 | App artifact = **static Go binary in S3**, pulled by cloud-init | ~12 MB, no runtime to install, no image pipeline in v1 | Golden AMI from day one (slow loop); Docker on EC2 (drifts toward the K8s story) |
| 005 | **SSM Session Manager** for all access | No port 22, no key pairs, no bastion, IAM-controlled, CloudTrail-audited | SSH bastion in a public subnet |
| 006 | ALB health check **shallow** (`/healthz`); deep check monitored separately | A dependency blip must not make the ASG terminate the whole fleet | Deep health check (correlated-failure trap) |
| 007 | ASG **target tracking** on `ALBRequestCountPerTarget` + CPU policy | The honest scaling signal for an API; demos far better under load | CPU-only, step scaling |
| 008 | NAT **Gateway** in prod, NAT **instance** in dev, S3 gateway endpoint in both | ~$33/mo → ~$3/mo; gateway endpoint is free and removes S3 traffic from NAT charges | NAT GW everywhere (cost); interface endpoints everywhere (~$7.30/mo each — worse) |
| 009 | RDS master password **managed by Secrets Manager** with rotation | Password never exists as plaintext you typed | `random_password` + manual secret (still lands in state) |
| 010 | **One CloudFront distribution, two origins** | Only free source of a valid TLS certificate; makes the ALB origin justified | Two distributions; CloudFront in front of the API alone |
| 011 | **No custom domain.** TLS via CloudFront default certificate | Free, valid, zero maintenance. The `us-east-1` cert constraint no longer applies | ACM + Route 53 public zone (needs a purchased domain); self-signed (unusable in a demo) |
| 012 | Two environments, both ephemeral | Cost (§4) | Three always-on environments |
| 013 | Route 53 **private** hosted zone for internal DNS | Keeps a Route 53 story without a public domain; decouples app config from AWS-generated endpoints | Hardcoding endpoints in config |
| 014 | ALB locked to CloudFront: managed prefix list + secret origin header | Otherwise the ALB's public DNS bypasses the CDN, WAF and cache entirely | ALB open to `0.0.0.0/0` |
| 015 | `dev-down` snapshots RDS; `dev-up` restores it | Makes the ephemeral workflow painless enough that you follow it | Reseeding data by hand every apply |
| 016 | **Terraform native tests** (`.tftest.hcl`) for every module | Catches broken variable contracts before an apply; rare in a portfolio | Manual apply-and-eyeball |
| 017 | **Blue/green as a second deploy strategy** alongside rolling | Two implemented strategies plus a written comparison is a far stronger interview answer than one | Rolling only |
| 018 | **AWS Backup** with a vault and cross-region copy, over RDS-native backups alone | Centralised plan, tested restores, cross-region DR at snapshot cost | RDS automated backups only |
| 019 | **AWS FIS** for fault injection, over manual console termination | The professional chaos tool; experiments are versioned, repeatable, and stoppable | Clicking "terminate" |
| 020 | SLOs defined **before** the game days, error budget computed after | Turns "it recovered fast" into "it consumed 12% of the monthly error budget" | Reporting raw recovery times only |

---

## 7. Repository structure

```
CloudForge/
├── README.md                     # The showcase. Written LAST, in a recruiter's voice.
├── PLAN.md                       # This file.
├── Makefile                      # dev-up / dev-down / prod-up / prod-down / gameday-N / verify
├── .pre-commit-config.yaml       # fmt · tflint · checkov · terraform-docs · gitleaks
│
├── terraform/
│   ├── bootstrap/                # State bucket. Local state, applied once, never touched again.
│   │
│   ├── modules/
│   │   ├── network/              # VPC, 3-tier subnets, IGW, NAT (gateway|instance), endpoints, flow logs
│   │   ├── security/             # All security groups in one place, referencing each other
│   │   ├── alb/                  # ALB, target groups (blue+green), listeners, rules
│   │   ├── compute/              # Launch template, ASG, IAM profile, scaling policies, lifecycle hooks
│   │   ├── database/             # RDS, subnet/parameter groups, secret, backups
│   │   ├── cache/                # ElastiCache subnet/parameter groups, Redis
│   │   ├── storage/              # S3: images, artifacts, logs — policies, versioning, lifecycle
│   │   ├── cdn/                  # CloudFront, OAC, WAF web ACL, cache policies
│   │   ├── dns/                  # Route 53 private hosted zone
│   │   ├── observability/        # Log groups, metric filters, alarms, dashboards, SNS, canary
│   │   ├── backup/               # AWS Backup vault, plan, cross-region copy
│   │   └── chaos/                # FIS experiment templates
│   │       └── tests/            # <module>.tftest.hcl for each of the above
│   │
│   └── environments/
│       ├── dev/                  # main.tf · variables.tf · outputs.tf · terraform.tfvars · backend.tf
│       └── prod/
│
├── app/                          # CloudStore API — Go, ~400 lines, deliberately trivial
│   ├── main.go  store.go  cache.go  objects.go  health.go
│   ├── migrations/
│   ├── docker-compose.yml        # Postgres + Redis + LocalStack — zero-cost local dev
│   └── Makefile
│
├── scripts/
│   ├── aws-inventory.sh          # read-only sweep, all regions          [BUILT]
│   ├── aws-teardown.sh           # dry-run by default, dependency order  [BUILT]
│   ├── deploy.sh                 # build → upload → LT version → instance refresh → wait
│   ├── load-test.js              # k6
│   ├── restore-test.sh           # automated backup restore drill
│   ├── cost-report.sh            # Cost Explorer by tag
│   └── gameday/                  # one script per experiment, each emitting a timestamped log
│
├── docs/
│   ├── architecture.md           # Diagrams, traffic and data flow, why each choice
│   ├── adr/                      # ADR-001 … ADR-020
│   ├── security.md               # Threat model, IAM policies, network boundaries, encryption
│   ├── well-architected.md       # Six-pillar self-review + remediations       ★
│   ├── slo.md                    # SLIs, SLOs, error budget policy             ★
│   ├── deployment-strategies.md  # Rolling vs blue/green, implemented + measured ★
│   ├── capacity-planning.md      # RPS per instance, derived scaling thresholds ★
│   ├── disaster-recovery.md      # RPO/RTO targets, runbooks, tested results
│   ├── runbooks/                 # account-teardown.md [BUILT], deploy, rollback, restore, on-call
│   ├── incidents/                # One postmortem per game day
│   ├── cost-analysis.md          # Real Cost Explorer numbers + optimizations
│   └── images/                   # Diagrams, dashboards, k6 output, screenshots
│
└── .github/workflows/
    ├── terraform.yml             # fmt · validate · tflint · checkov · test · plan · gated apply
    ├── app.yml                   # test · build · upload · instance refresh
    ├── drift.yml                 # scheduled plan, alerts on drift              ★
    ├── restore-test.yml          # scheduled backup restore drill               ★
    └── nightly-destroy.yml       # dev teardown backstop                        ★

★ = differentiator, see §9
```

---

## 8. Milestones

Each has a **Definition of Done** and an **Evidence** artifact — the thing that ends up in the README. Produce evidence as you go; reconstructing it later never happens.

**~18 weeks at 8–10 h/week.** Sept 2026 → roughly Feb 2027, leaving four months of margin before June 2027.

---

### M0 — Foundations · week 1 · 4h

- AWS Budget $20 + alerts at 50/80/100%; CloudWatch billing alarm → SNS → email (**confirm the subscription email**).
- **Cost Anomaly Detection** (free).
- **CloudTrail** — one trail, management events, → S3. First trail per region is free; you get an audit log of every API call for the whole project.
- Root MFA ✅ (done 2026-09-04). Replace the `cloudforge-admin` access key with **IAM Identity Center** (`aws sso login`, short-lived credentials), then delete the key.
- `terraform/bootstrap/` — S3 state bucket: versioned, encrypted, public access blocked, `use_lockfile` in consumers. Local state, applied once, committed, never touched again.
- `git init`, `.gitignore` (`*.tfstate*`, `.terraform/`, `*.tfvars`), `.pre-commit-config.yaml` (fmt, tflint, checkov, terraform-docs, gitleaks).
- Provider `default_tags` shared by both environments.

**DoD:** `terraform init` in an empty env dir reaches the S3 backend and takes a lock.
**Evidence:** ADR-001; budget screenshot; `docs/security.md` opening section.

---

### M1 — Network · week 2 · 8h

- VPC `10.0.0.0/16`, two AZs, **three tiers** (public / app / data). Three tiers is what production looks like and costs nothing extra.
  ```
  10.0.1.0/24  public-a     10.0.2.0/24  public-b
  10.0.11.0/24 app-a        10.0.12.0/24 app-b
  10.0.21.0/24 data-a       10.0.22.0/24 data-b
  ```
- IGW, route tables, `nat_type = "gateway" | "instance"` (ADR-008), S3 gateway endpoint, VPC Flow Logs → CloudWatch.
- Throwaway instance in a private subnet reachable **only** via SSM Session Manager.
- First `.tftest.hcl` — assert CIDR maths, subnet count, and that no route table sends `0.0.0.0/0` to the IGW from a private subnet.

**DoD:** `terraform destroy` cleanly removes everything. Run it twice.
**Evidence:** Network diagram; terminal recording of an SSM session into a private instance with no SSH key in existence.

---

### M2 — CloudStore API (Go) · week 3 · 8h — **hard timebox**

```
GET    /api/products              Redis-cached list
GET    /api/products/{id}         Redis-cached, TTL 60s
POST   /api/products
DELETE /api/products/{id}
POST   /api/products/{id}/image   → S3

GET    /healthz    shallow — 200 if the process lives. THE ALB CHECKS THIS   ← ADR-006
GET    /readyz     deep — pings Postgres + Redis. Monitored, NOT used by the ALB
GET    /whoami     instance-id + AZ from IMDSv2
```

`/whoami` is five lines and is how you *visually demonstrate* load balancing and AZ distribution on video. Include it.

Dependencies, minimal: `pgx/v5`, `go-redis/v9`, `aws-sdk-go-v2`, `golang-migrate`.

Requirements:
- Config from env vars; DB credentials from Secrets Manager at boot.
- `docker-compose.yml` (Postgres + Redis + LocalStack) — app dev costs $0.
- **Graceful shutdown** on `SIGTERM`, drain window > ALB deregistration delay. Without it, M8's "0 failed requests" will not happen.
- **Redis fails open** to Postgres. This makes game-day #5 a graceful-degradation demo instead of an outage.
- **Structured JSON logging** with a request ID — required for the CloudWatch metric filters in M7.
- Build: `CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w"`.

> If you are still writing app code in week 4, cut endpoints. Nobody is hiring you for this API.

**DoD:** runs against docker-compose; `go test ./...` green; cross-compiles for arm64.
**Evidence:** none public — scaffolding. Say so in the README.

---

### M3 — Compute · weeks 4–5 · 10h

- IAM role + instance profile, **hand-written least privilege**:
  - `AmazonSSMManagedInstanceCore` (this managed policy is fine)
  - `s3:GetObject` on the artifacts bucket only
  - `s3:PutObject|GetObject|DeleteObject` on the images bucket only
  - `secretsmanager:GetSecretValue` on two specific ARNs
  - `cloudwatch:PutMetricData`, `logs:*` scoped to your log groups
  - **No `Resource: "*"` anywhere.**
- Launch template: Amazon Linux 2023 ARM. User-data installs the CloudWatch agent, pulls the binary, writes a systemd unit (`Restart=always`, `TimeoutStopSec` matched to the drain window). No runtime to install.
- ASG across both AZs: `min=2 desired=2 max=6`, health check type `ELB`, 300s grace.
- Instance refresh: `MinHealthyPercentage=100`, `InstanceWarmup=180`.
- **ASG lifecycle hook** on terminate, so draining completes before the instance dies.
- **IMDSv2 required** (`http_tokens = "required"`) — mitigates SSRF credential theft, and a good thing to be able to explain.

**DoD:** terminate an instance by hand → replacement appears and serves traffic unattended.
**Evidence:** IAM policy walkthrough in `docs/security.md`.

---

### M4 — Load balancing, edge TLS, WAF · weeks 5–6 · 10h

- ALB in public subnets. **Two target groups** (blue and green) for M8's blue/green. Shallow `/healthz` check, 10s interval, 2/2 thresholds, 30s deregistration delay. Access logs → S3.
- CloudFront distribution, `/api/*` behavior, caching disabled on that path. **HTTPS free** (ADR-011).
- **AWS WAF** on the distribution with AWS managed rule groups (`CommonRuleSet`, `KnownBadInputs`, `AmazonIpReputationList`) plus a rate-based rule. ~$7/month, pennies per game day.
- SG chain, explicitly: `CloudFront prefix list → ALB:80` · `ALB-SG → App-SG:8080` · `App-SG → RDS-SG:5432` · `App-SG → Redis-SG:6379`. **Nothing permits `0.0.0.0/0`.** ALB additionally requires the secret origin header (ADR-014).
- Route 53 **private** hosted zone: `db.cloudforge.internal`, `cache.cloudforge.internal`.

**DoD:** `curl https://<dist>.cloudfront.net/api/whoami` returns alternating instance IDs with a valid cert, while `curl http://<alb-dns>/...` fails.
**Evidence:** SSL Labs grade; alternating-`whoami` recording; the ALB-unreachable side-by-side; **a WAF-blocked SQL-injection attempt** (send `' OR 1=1--`, screenshot the 403 and the WAF sampled-requests log). That last one is a genuinely good security artifact.

---

### M5 — RDS PostgreSQL · weeks 6–7 · 8h

- Subnet group across the **data** tier. `publicly_accessible = false`.
- `manage_master_user_password = true` → AWS-managed secret with rotation (ADR-009).
- KMS-encrypted storage, Performance Insights on, `deletion_protection` on in prod / off in dev.
- Multi-AZ on in prod, off in dev.
- Parameter group: `log_min_duration_statement`, `log_connections` → CloudWatch Logs.
- App connects via `db.cloudforge.internal`. `pgxpool` tuned for failover: short `MaxConnLifetime`, low `HealthCheckPeriod`.
- **Snapshot lifecycle** (ADR-015): `snapshot_identifier` + `final_snapshot_identifier`; wire `make dev-down`/`dev-up` and test the round trip before moving on.

**DoD:** app reads/writes through RDS; `psql` from the internet refused; `psql` from an instance via SSM works.
**Evidence:** SG diagram; connection-refused capture.

---

### M6 — Cache, storage, CDN · weeks 7–8 · 10h

**ElastiCache Redis** — data subnets, encryption in transit and at rest, AUTH token in Secrets Manager, `cache.t4g.micro`. Cache-aside, TTL 60s, invalidate on write, fails open.
> Measure: p95 latency cold vs warm, RDS `DatabaseConnections` before/after. A cache without a measurement is decoration.

**S3** — `images` (versioned, CDN origin), `artifacts` (versioned), `logs` (lifecycle → Glacier IR → expire). All: public access blocked, SSE, TLS-only bucket policy.

**CloudFront** — add the `/images/*` behavior with **OAC**, long TTL, compression. One distribution, two origins, two cache policies (ADR-010).

**DoD:** image serves from the CDN; direct S3 URL returns 403.
**Evidence:** cache hit-ratio and latency table; 403-vs-200 side-by-side; both cache behaviours' hit ratios.

---

### M7 — Observability and SLOs · weeks 9–10 · 12h ★

- CloudWatch agent: memory and disk (not available from the hypervisor by default) plus app logs → `/cloudforge/<env>/app`.
- Metric filters on structured logs: error count, exception count → custom metrics.
- **Alarms**, each → SNS → email:

| Alarm | Threshold |
|---|---|
| ALB `UnHealthyHostCount` | ≥ 1 for 2 min |
| ALB `HTTPCode_Target_5XX_Count` | > 10 in 5 min |
| ALB `TargetResponseTime` p95 | > 1s for 5 min |
| ASG `GroupInServiceInstances` | < 2 |
| EC2 CPU | > 80% for 10 min |
| RDS CPU / free storage / connections | > 80% / < 2 GB / > 80% max |
| Redis memory / evictions | > 80% / > 0 |
| Billing | > budget |

- **Composite alarm** for "service degraded" (unhealthy hosts AND elevated 5xx) — shows alert-fatigue awareness.
- **Two dashboards**: a **Four Golden Signals** operational dashboard (latency, traffic, errors, saturation — name it that, it signals SRE literacy) and an **SLO dashboard** (§10).
- **CloudWatch Synthetics canary** hitting `/api/products` from outside AWS every 5 minutes. ~$0.0012/run. Gives external availability measurement independent of your own metrics — which is what an SLI should be.
- **SLOs defined here, before any game day** (§10, ADR-020).

**DoD:** trigger a real alarm and receive the email; the canary reports availability.
**Evidence:** both dashboards; the alarm email; **a runbook per alarm** in `docs/runbooks/` — *what an on-call engineer does when this fires*. Runbooks are what make this read as operations rather than a lab.

---

### M8 — CI/CD, testing, drift detection · weeks 10–11 · 12h ★

**`terraform.yml`** — PR: `fmt -check` → `validate` → `tflint` → `checkov` → **`terraform test`** → `plan` as a PR comment → `infracost diff`. Merge to `main`: auto-apply dev; prod behind manual environment approval.

**`app.yml`** — `go test` → `go vet` → `govulncheck` → cross-compile arm64 → upload to versioned S3 key → new LT version → `start-instance-refresh` → poll.

**`drift.yml`** ★ — scheduled daily `terraform plan -detailed-exitcode`; non-empty plan → GitHub issue + SNS. *"I detect manual console changes automatically"* is a real operations answer almost no portfolio has.

**`nightly-destroy.yml`** ★ — `terraform destroy` on dev at 23:00, backstop for the night you forget.

- **GitHub OIDC to AWS**, trust policy scoped to your repo *and* branch. No static keys anywhere. Document the trust policy in `docs/security.md` — "how does your CI authenticate to AWS" is a near-guaranteed interview question.
- **Blue/green deployment** ★ as a second strategy: two target groups, ALB listener weight shift 100/0 → 0/100, with a soak window and one-command rollback.
- **k6 in CI with thresholds** as a performance regression gate.

**DoD:** a one-line change reaches prod with zero downtime via both strategies.
**Evidence:** the deploy measurement (pipeline duration, refresh duration, k6 showing **0 failed requests**); `docs/deployment-strategies.md` comparing rolling and blue/green with measured numbers; a drift alert screenshot from a deliberate console change.

---

### M9 — Environments, module hardening, public module · week 12 · 8h

- Every hardcoded value → module variable with defaults and `validation` blocks.
- `dev` vs `prod` tfvars differ **only** in: sizes, counts, `multi_az`, `nat_type`, retention, deletion protection.
- `terraform-docs`-generated README per module.
- `.tftest.hcl` coverage for every module (ADR-016).
- ★ **Publish one module to the public Terraform Registry** — repo named `terraform-aws-<name>`, semver tags. A public URL a recruiter can click, with a download count. Free, and very few juniors have one.

**DoD:** both environments apply from identical module code; `terraform test` green across all modules.
**Evidence:** side-by-side tfvars diff captioned *"same modules, different posture"*; the Registry link.

---

### M10 — Security hardening and Well-Architected review · week 13 · 10h ★

- **AWS Well-Architected Tool** (free, in console) — run a formal review of the workload against all six pillars. Record every finding, remediate what you can, and document what you consciously accepted and why.
  > *"I ran a Well-Architected review against my own architecture and remediated 14 of 19 findings; the remaining 5 are documented accepted risks with rationale"* is an exceptionally strong sentence, and almost nobody at your stage has it.
- **GuardDuty** enabled during its 30-day trial window; document findings; disable before it bills.
- **Checkov custom policy** — e.g. "no security group may allow `0.0.0.0/0` on port 22", "every S3 bucket must block public access", "all resources must carry the required tags". Enforced in CI.
- **Threat model** in `docs/security.md`: what an attacker would try, what stops them at each layer, what you consciously did not defend against.
- **Encryption inventory**: every data store, at rest and in transit, with the key type.
- **IAM Access Analyzer** — free; check for unintended external access.

**DoD:** Well-Architected review complete; all high-severity findings either fixed or documented as accepted.
**Evidence:** `docs/well-architected.md`; GuardDuty findings screenshot; the custom Checkov policy failing a deliberately bad PR.

---

### M11 — Backup and DR automation · week 14 · 10h ★

- **AWS Backup**: vault, backup plan, RDS + EBS selection by tag, retention, lifecycle to cold storage, **cross-region copy** to a second region. Snapshot-cost only, and it turns DR from a paragraph into a configuration.
- **SSM Automation runbooks** ★ — executable recovery, not prose. E.g. a document that restores the latest RDS snapshot into a new instance, updates the private-zone DNS record, and verifies connectivity. *"My runbooks are executable"* beats *"I wrote a runbook."*
- **`restore-test.yml`** ★ — scheduled weekly: restore the latest snapshot into a temporary instance, run a data-integrity check, record the restore duration, destroy it. **Automated backup verification is something most production teams do not do**, and it produces a recurring measurement.
- **DR strategy comparison** in `docs/disaster-recovery.md`: backup/restore vs pilot light vs warm standby vs active-active — cost, RPO and RTO for each, which you chose and why. Shows you know the options, not just the one you built.

**DoD:** the restore drill runs unattended and reports a duration.
**Evidence:** restore-test workflow output over several weeks; the SSM Automation execution log; the strategy comparison table.

---

### M12 — Game days · weeks 15–16 · 12h — the highest-value weeks

Prod comes up for a session, experiments run back to back, evidence is captured, prod goes down. Template for every experiment:

**hypothesis → method → timeline → measurement → error-budget impact → what surprised me → what I changed as a result**

> *"What I changed as a result"* separates an engineer from a screenshot collector. Fill it in every time, even when the answer is "lengthened the ASG grace period by 60s."

| # | Experiment | Method | Measure |
|---|---|---|---|
| 1 | Instance failure | **FIS** `aws:ec2:terminate-instances` | Detection → replacement → healthy → full capacity. Requests failed. |
| 2 | AZ impairment | **FIS** network-disrupt, or detach one AZ's subnet | Does the ALB shift all traffic? Does the ASG rebalance? Error spike? |
| 3 | Load and scaling | k6 ramp 10 → 200 VUs | Scale-out trigger latency, 2→N instances, p50/p95/p99 through the ramp, scale-in after |
| 4 | RDS failover | `reboot-db-instance --force-failover` | Unavailability window, did `pgxpool` recover unaided, error count, time to full recovery |
| 5 | Cache failure | Kill the Redis node | Graceful degradation to Postgres, or 500s? *If it 500s, that is a real finding — fix it and re-run.* |
| 6 | Rolling deploy under load | Instance refresh during k6 | Failed requests (target 0), rollout duration |
| 7 | Blue/green under load | Listener weight shift during k6 | Same, plus rollback time |
| 8 | **CPU stress** | **FIS** `aws:ssm:send-command` CPU stress | Does the CPU alarm fire? Does target tracking scale correctly? |
| 9 | Full rebuild | `destroy` → `apply` | Wall-clock to a serving environment. **The marquee number.** |
| 10 | **Region-loss simulation** | Restore from cross-region backup into the DR region | Actual RTO for total region loss |

Run k6 during **every** experiment so you always have a client-side view, not just AWS's.

**Evidence:** `docs/incidents/01…10.md`, each a postmortem with timeline, graphs, error-budget impact, and resulting changes.

---

### M13 — DR validation and capacity planning · week 17 · 8h

- State RPO/RTO targets *before* testing, then report actual vs target — **including where you missed**. A missed target you diagnosed is more credible than a perfect scorecard.
- Honest data-loss analysis: what is recoverable, what is not (in-flight requests, cache), why that is acceptable.
- ★ **`docs/capacity-planning.md`** — from the load tests: max sustainable RPS per instance, the saturation point, where the bottleneck moved (app → DB → cache), and the scaling thresholds *derived from those numbers* rather than guessed. This is the difference between "I set CPU at 70%" and "I set it at 70% because throughput degrades non-linearly past 74%."
- Error-budget report for the game-day period (§10).

**Evidence:** DR results table; capacity-planning doc with graphs.

---

### M14 — Cost analysis, polish, publication · week 18 · 10h

- **Cost:** Cost Explorer by tag for the real period. Document each optimization (Graviton, NAT instance, S3 gateway endpoint, lifecycle policies, ephemeral environments) with before/after numbers. Baseline is already captured: **$0.77/day before teardown, $0.00/day after** (§16).
- **README** — written last, for a recruiter reading for 90 seconds. Architecture diagram in the first screenful, then the measurements table, then depth below the fold.
- **Architecture diagram** — draw.io or Excalidraw, exported PNG. ASCII in the terminal; a real image in the README.
- ★ **Screen recording, 3–5 minutes**: apply → curl → FIS kills an instance → dashboard reacts → self-heals. This outperforms every screenshot you will ever take.
- ★ **Write-up** — a blog post or LinkedIn article series on the game-day results and what surprised you. Free, findable by recruiters, and forces you to articulate the project the way you will in an interview. The "what surprised me" fields from M12 are the draft.
- Repo polish: LICENSE, badges, a `docs/` index, and pinned issues showing planned work.

---

## 9. The differentiators

Everything marked ★ above. These are what separate this from the hundreds of "I built a VPC with Terraform" repos. Ordered by CV impact per hour spent:

| # | Addition | Why it lands | Cost | Effort |
|---|---|---|---|---|
| 1 | **SLOs + error budget** (§10) | Turns "it recovered in 2m17s" into "it consumed 12% of the monthly error budget". This is how SRE teams actually talk. Almost no junior portfolio has it. | $0 | 4h |
| 2 | **Well-Architected review** | A formal AWS artifact. "I reviewed my own architecture against all six pillars and remediated 14 of 19 findings." | $0 | 6h |
| 3 | **Automated backup restore testing** | Most *production* teams do not verify their backups. A weekly job that restores, checks integrity and reports duration is a genuinely senior habit. | ~$0 | 4h |
| 4 | **Drift detection** | "I detect manual console changes automatically." Immediately relatable to anyone who has operated Terraform in a team. | $0 | 2h |
| 5 | **Two deployment strategies + comparison** | Rolling *and* blue/green, both measured. Answers "how would you deploy this?" with data instead of theory. | $0 | 5h |
| 6 | **Terraform native tests** | `terraform test` is recent and rare. "My modules have tests" is a sentence very few candidates can say. | $0 | 4h |
| 7 | **AWS FIS** | Real chaos-engineering tooling, versioned and repeatable, rather than clicking terminate. | ~$1 | 3h |
| 8 | **Published Terraform module** | A public URL with a download count. Verifiable, permanent, clickable from your CV. | $0 | 2h |
| 9 | **Capacity planning from measurements** | Scaling thresholds *derived* rather than guessed. Shows engineering judgement. | $0 | 3h |
| 10 | **SSM Automation runbooks** | Executable recovery, not prose. | $0 | 3h |
| 11 | **WAF with a blocked-attack screenshot** | A concrete, visual security control. | ~$7/mo prorated | 2h |
| 12 | **Synthetics canary** | External availability measurement — what an SLI should be measured from. | ~$0.35/mo | 1h |
| 13 | **Public write-up** | Findable by recruiters; rehearses your interview narrative. | $0 | 4h |
| 14 | **Screen recording** | The single highest-conversion artifact in the whole repo. | $0 | 2h |

**If time runs short, cut from the bottom.** 1–5 are the ones that change how a hiring manager reads the project.

### Considered and rejected

Kept out deliberately, and worth being able to say why: multi-region active-active (cost and complexity for a demo), EKS/ECS (Pitstop's territory), Lambda microservices (dilutes the EC2/ASG story), X-Ray tracing (interesting, but a single-service app has nothing to trace), AWS Config (per-evaluation billing for little added signal over Checkov), Packer golden AMIs (slows the iteration loop; noted as a v2 idea), Organizations/SCPs (needs a multi-account setup), Aurora (Multi-AZ RDS already demonstrates the concept at a fraction of the price).

---

## 10. SLOs, SLIs and the error budget ★

Defined in M7, **before** any game day (ADR-020). Numbers are the starting proposal; adjust once you have baseline data, and document why you changed them.

**SLIs** (measured by the Synthetics canary and ALB metrics — from outside, not from the app's own view):

| SLI | Definition |
|---|---|
| Availability | successful canary runs ÷ total canary runs |
| Latency | proportion of requests with `TargetResponseTime` < 500 ms |
| Correctness | proportion of responses that are not 5xx |

**SLOs** (30-day rolling):

| Objective | Target | Monthly error budget |
|---|---|---|
| Availability | 99.5% | 3h 39m of downtime |
| Latency (p99 < 500 ms) | 99% | 1% of requests may be slow |
| Correctness | 99.9% | 0.1% of requests may 5xx |

**Error budget policy** — write it down and follow it during the game days:

- Budget > 50% remaining → ship freely, run experiments.
- Budget < 50% → no new experiments until the cause is understood.
- Budget exhausted → deploy freeze; reliability work only until the window rolls.

**Why this matters more than it looks.** Every game day in M12 consumes error budget. Reporting *"experiment 4 consumed 31% of the monthly availability budget, which is why the RDS failover result is the one I acted on first"* demonstrates prioritisation grounded in data. That is a level of reasoning most candidates cannot produce at all, and it costs you nothing but a spreadsheet.

---

## 11. The measurements table

The README's core. Fill from M12. **Never invent these** — an interviewer who senses a fabricated metric discounts the whole project.

```markdown
| Scenario                     | Detection | Recovery | Requests failed | Error budget |
|------------------------------|-----------|----------|-----------------|--------------|
| EC2 instance termination      | __s       | __m __s  | __              | __%          |
| AZ impairment                 | __s       | __m __s  | __              | __%          |
| RDS Multi-AZ failover         | __s       | __s      | __              | __%          |
| Redis node failure            | __s       | __s      | __ (degraded)   | __%          |
| CPU saturation → scale-out    | __s       | __m __s  | __              | __%          |
| Rolling deploy under load     | n/a       | __m __s  | __              | __%          |
| Blue/green deploy under load  | n/a       | __m __s  | __              | __%          |
| Full rebuild from zero        | n/a       | __m __s  | n/a             | n/a          |
| Cross-region restore (DR)     | n/a       | __m __s  | n/a             | n/a          |

RPO target: __   measured: __
RTO target: __   measured: __
Max sustainable RPS per t4g.micro: __
Cost per hour, full prod: $__     Resting cost: $__/month
```

---

## 12. Portfolio artifacts checklist

What must exist when you call this done. Tick these, not the milestones.

- [ ] README with diagram, measurements table and cost figures in the first screenful
- [ ] 3–5 minute screen recording of a real failure and recovery
- [ ] Architecture diagram (PNG, not ASCII)
- [ ] 20 ADRs
- [ ] 10 incident reports with timelines and resulting changes
- [ ] `docs/well-architected.md` with findings and remediations
- [ ] `docs/slo.md` with the error-budget report
- [ ] `docs/deployment-strategies.md` with measured comparison
- [ ] `docs/capacity-planning.md` with graphs
- [ ] `docs/disaster-recovery.md` with tested RPO/RTO
- [ ] `docs/cost-analysis.md` with before/after numbers
- [ ] `docs/security.md` with threat model and IAM walkthrough
- [ ] Runbook per alarm, plus executable SSM Automation runbooks
- [ ] One module published to the Terraform Registry
- [ ] Green CI with tests, security scanning and drift detection
- [ ] A public write-up
- [ ] Six CV bullets with real numbers (§14)

---

## 13. Risks

| Risk | Mitigation |
|---|---|
| **Credit burn** | Budget + billing alarm + anomaly detection; both environments ephemeral; nightly auto-destroy; weekly `aws-inventory.sh` |
| **Leaked credentials** | `gitleaks` pre-commit and in CI; OIDC in CI; IAM Identity Center locally instead of long-lived keys |
| **`terraform destroy` fails, resources linger** | Test destroy in M1 and after every milestone; deletion protection as a variable; `aws-inventory.sh` after every teardown |
| **Scope creep** | §3 non-goals and the §9 rejected list. Re-read monthly. |
| **App work eating infra time** | M2 hard-timeboxed to one week. Cut endpoints, not milestones. |
| **Exams / thesis collision** | Milestones are independent enough to pause between. Never pause with an environment running. |
| **Over-building the differentiators** | §9 is ordered by value per hour. Cut from the bottom, not the top. |
| **Evidence not captured as you go** | Every milestone has an Evidence line. Treat a milestone as incomplete without it — reconstructing at the end never happens. |

---

## 14. CV output

> **CloudForge — Highly Available Production Cloud Platform**
> *AWS · Terraform · EC2 Auto Scaling · ALB · RDS · ElastiCache · S3 · CloudFront · WAF · CloudWatch · IAM · Go · GitHub Actions*
>
> - Designed and provisioned a multi-AZ AWS production environment entirely as code, with tested, reusable Terraform modules covering networking, compute, load balancing, database, caching, storage, CDN, backup and observability, deployed to two environments from a single module set with remote state and per-environment isolation.
> - Defined availability and latency SLOs with an error-budget policy, then validated them through **10 controlled failure-injection experiments using AWS FIS**: instance termination recovered in **__**, RDS Multi-AZ failover in **__**, and AZ impairment in **__**, with **__** failed requests.
> - Implemented and measured two zero-downtime deployment strategies without Kubernetes — rolling via ASG instance refresh and blue/green via ALB target-group weighting — verified under sustained load with **0** failed requests.
> - Enforced least-privilege IAM, private-subnet isolation, WAF managed rule groups, Secrets Manager with managed rotation, encryption at rest and in transit, and keyless access via SSM Session Manager and GitHub OIDC; completed an **AWS Well-Architected review**, remediating **__** of **__** findings.
> - Automated disaster recovery with AWS Backup, cross-region snapshot copy and a **scheduled restore-verification job**; achieved a tested RTO of **__** and a full environment rebuild from zero in **__**.
> - Reduced infrastructure cost **__%** through Graviton instances, NAT instance substitution, S3 gateway endpoints and ephemeral environment scheduling, bringing resting cost to **$__/month** with automated drift detection and budget alerting.

**LinkedIn headline version:** *"Built a multi-AZ AWS platform in Terraform with tested SLOs, chaos experiments and automated DR — resting cost under $2/month because it exists as code."*

---

## 15. Interview preparation

You must answer these cold. If you cannot, the project is not finished.

**Architecture:** Why three subnet tiers? · Why is your ALB health check shallow, and what breaks if it isn't? · How does traffic reach a private-subnet instance, and how do *you*? · Why NAT Gateway over NAT instance — and when is that the wrong call? · Why did you not use Kubernetes here?

**Resilience:** Walk me through an RDS Multi-AZ failover, second by second. · What happens if an entire AZ goes away? · What breaks first under load, and how do you know? · What is your RPO, and what data would you actually lose?

**Operations:** How do you deploy without downtime, and how do you roll back? · What are your SLOs and how did you choose them? · What is an error budget and what do you do when it's exhausted? · How do you know your backups work?

**Terraform:** Where does state live and what stops two applies colliding? · How do you test a module? · How do you detect someone changing things in the console? · How would you onboard a second engineer to this repo tomorrow?

**Security:** How does your CI authenticate to AWS? · Walk me through your IAM policy for the instance role. · What would an attacker try first, and what stops them? · What did the Well-Architected review find that you *didn't* fix, and why?

**Cost:** What does this cost to run, and what did you do to reduce it? · Where would you spend more if this were real revenue-generating traffic?

---

## 16. Account status

| | |
|---|---|
| Account | `<ACCOUNT_ID>`, created 2026-09-02, EMEA (Amazon Web Services EMEA SARL) |
| Credits | **$158.46** remaining, all expiring **2027-09-02** ($100 signup + 3 × $20 activity) |
| Free tier | **No legacy 12-month tier.** Post-July-2025 model — credits only. "Always free" offers apply (§17.4) |
| Root MFA | ✅ enabled 2026-09-04 |
| Local access | IAM user `cloudforge-admin`, profile `cloudforge`. **To be replaced by IAM Identity Center in M0.** |

### Teardown log — 2026-09-04 ✅

Cause of the initial $1.54: a **Pitstop EKS deployment in `us-east-1`** (the machine still held a `pitstop-eks` CLI profile pinned to that region, created the same day as the account). EKS bills $0.10/hr for the control plane alone, matching $1.54 over ~15 hours.

Removed via `docs/runbooks/account-teardown.md`: EKS cluster and CloudFormation stacks, Kubernetes-created load balancers, RDS, EC2, NAT gateways, Elastic IPs, storage orphans.

Verified with `scripts/aws-inventory.sh` across **all 17 enabled regions**:

```
GLOBAL      — clean (no S3, CloudFront or Route 53 resources)
16 regions  — clean
us-east-1   — 1 KMS key in its 7-day deletion window (~$0.23, unavoidable)
```

**Cost baseline for `docs/cost-analysis.md`: ~$0.77/day before, $0.00/day after.**

Outstanding: confirm flat spend on the Bills page at +24h and Credits at +48h. Billing lags ~24h, so same-day figures prove nothing.

---

## 17. Decision log and open items

| # | Decision | Status |
|---|---|---|
| 1 | App stack | ✅ **Go** — cheapest, fastest boot, trivial by design |
| 2 | CI platform | ✅ **GitHub Actions** with OIDC to AWS |
| 3 | Custom domain | ✅ **None.** CloudFront default certificate; private hosted zone for internal DNS |
| 4 | Environments | ✅ `dev` + `prod`, both ephemeral |
| 5 | Region | ✅ **`eu-west-3`** (Paris) — better latency, and makes the choice deliberate rather than inherited from the cleanup |
| 6 | Budget | ✅ **$158 credits** to 2027-09-02. Plan needs no tightening |
| 7 | Account cleanup | ✅ Complete, verified across 17 regions |

**Open:**

1. **`[PENDING]` Free Plan vs Paid Plan.** AWS overhauled the free tier in July 2025 and new accounts choose a plan. Check **Billing → Account / Free tier**. Under a Free Plan the account caps and suspends rather than billing — safe, but it may **restrict which services you can launch**, which would block NAT Gateway, ElastiCache or WAF and force a rework of M1/M4/M6. The fact that EKS ran at all is weak evidence of a Paid Plan, but confirm it before M1.
2. **`[PENDING]` Remaining activity credits.** 3 of 5 "Explore AWS" activities claimed — **~$40 may still be available**. Check **Billing → Free tier**. Claim only what you can immediately tear down.
3. **`[PENDING]` Credit service coverage.** Each credit row has a *"See complete list of services"* link. Confirm the $100 credit covers NAT Gateway and data transfer specifically — two of the four largest line items in §4.
4. **`[PENDING]` Public repo?** Decide before the first push. If public: no account IDs, no ARNs containing your account number, no `.tfvars` with secrets, `gitleaks` over the full history first.
5. **`[PENDING]` Billing verification.** Bills at +24h, Credits at +48h (§16).

---

## 18. Documentation and proof of work

### 18.1 The problem this section solves

Anyone can now generate a repository full of plausible Terraform in an afternoon. A hiring manager knows that. So the question is not *"does this repo contain good infrastructure code?"* — it is **"did this person actually do this, and do they understand it?"**

Everything below is designed to answer that second question. The repo is not documentation of the work; **the repo is the evidence.**

### 18.2 What actually convinces, ranked

| Rank | Signal | Why it is hard to fake |
|---|---|---|
| 1 | **Commit history spread across months** | A repo with ~250 commits between Sept and Feb reads completely differently from one with 4 commits on a single day. The commit graph is the first thing an engineer checks, and a project dumped in one push looks bought or generated. This is the single strongest signal and it costs you nothing except committing as you go. |
| 2 | **The 3–5 minute screen recording** | A real terminal and a real console showing a real instance dying and the system healing. Nearly impossible to fabricate convincingly. |
| 3 | **Incident reports with real timestamps and graphs** | CloudWatch graphs carry real dates and real shapes. The "what surprised me" field especially — genuine surprise reads differently from invented surprise. |
| 4 | **ADRs committed on the day the decision was made** | A dated decision log is a timeline of your thinking. Twenty ADRs added in one commit at the end proves nothing; twenty committed across five months proves everything. |
| 5 | **Public CI history** | GitHub Actions run logs are public on a public repo. Real runs, real failures, real fixes. A green badge with 300 runs behind it is evidence. |
| 6 | **Measurements you can defend in conversation** | §15. If you can explain *why* the RDS failover took as long as it did, you did the work. If you can't, no amount of documentation helps. |
| 7 | **Published Terraform module** | A registry URL with a download count. External, permanent, verifiable. |
| 8 | **A dated write-up** | Timestamped, findable, and it forces you to articulate the project the way you will in an interview. |

Note what is *not* on this list: volume of code, number of AWS services, or how polished the README looks. Those are table stakes, not proof.

### 18.3 Commit discipline — start this at M0, not later

This is the habit that matters most, and it is free.

- **Commit at the end of every working session**, even if the session was "read docs and wrote one ADR." Small commits across months beat large commits across days.
- **Write commit messages that carry reasoning**, not just action:
  ```
  bad:   "update alb module"
  good:  "alb: switch health check to /healthz (shallow)

         Deep check on /readyz meant a single RDS blip marked every
         target unhealthy at once and the ASG cycled the whole fleet.
         See ADR-006."
  ```
  Someone reading `git log` should be able to reconstruct your reasoning. That log is itself an artifact you can point at.
- **Commit the ADR in the same commit as the change it describes.** That pairs the decision with the code permanently.
- **Commit evidence when you capture it** — a dashboard screenshot goes in on the day you took it, not in a "add docs" commit at the end.
- **Never squash the project history into a clean final state.** The mess is the proof.

### 18.4 GitHub features to actually use

- **Public repository.** It cannot be evidence if nobody can open it. (Resolves open item 4 — go public, after the security review in §18.6.)
- **Issues, one per milestone**, closed by the PR that completes them. Free project-management trail.
- **Pull requests even though you are solo.** Branch per milestone, PR with the `terraform plan` output in the description, merge. This produces a reviewable history *and* rehearses the workflow you will use at work. It is also how the CI gates in M8 become visible to a reader.
- **GitHub Projects board** mapped to M0–M14, so a visitor sees the plan and the progress.
- **Releases with tags** at meaningful points (`v0.1-network`, `v0.2-compute`, `v1.0-first-full-prod`). Gives the repo a visible arc.
- **Actions badges** in the README — build, tests, security scan, drift check.
- **GitHub Pages** serving `docs/` — free, and makes the incident reports and ADRs browsable rather than requiring a clone.
- **Repo topics**: `aws`, `terraform`, `sre`, `high-availability`, `disaster-recovery`, `chaos-engineering`, `infrastructure-as-code`.
- **Pin the repo** on your GitHub profile.
- **A `docs/` index** so the depth is navigable rather than a folder of files.

### 18.5 README structure — the 90-second read

Be realistic about the audience. A recruiter gives it 90 seconds and reads only the first screenful. The engineer who interviews you reads the rest, and reads it properly. Write for both, in that order.

```markdown
# CloudForge — Highly Available Production Cloud Platform

[badges: terraform CI · tests · checkov · drift check · license]

> A multi-AZ AWS production environment built entirely in Terraform, with tested
> SLOs, automated disaster recovery, and ten controlled failure experiments.
> Resting cost: under $2/month, because it exists as code.

[ARCHITECTURE DIAGRAM — full width, above the fold]

## Measured results
[the §11 table — real numbers, first screenful]

## 3-minute demo
[embedded recording or GIF: apply → curl → kill an instance → self-heal]

---
## What this is
Two paragraphs. Say plainly that the application is a deliberately trivial prop
and the infrastructure is the product.

## Architecture      → docs/architecture.md
## Decisions (20 ADRs) → docs/adr/
## Failure experiments → docs/incidents/
## SLOs & error budget → docs/slo.md
## Security & Well-Architected review → docs/security.md, docs/well-architected.md
## Disaster recovery   → docs/disaster-recovery.md
## Cost analysis       → docs/cost-analysis.md
## Running it yourself → make dev-up
```

The rule: **numbers above the fold, prose below it.** Recovery times, request counts and dollar figures in the first screenful; explanation underneath for whoever keeps scrolling.

### 18.6 What to redact before going public

Run this review once, before the first push, then keep `gitleaks` in pre-commit and CI:

- **AWS account ID** — appears in ARNs, screenshots, and CloudWatch console URLs. Replace with `<ACCOUNT_ID>` in docs; blur it in screenshots.
- **Access keys** — should never exist in the repo; `gitleaks` over the full history before the first push, not just the working tree.
- **CloudFront distribution IDs and ALB DNS names** for anything still running. Once an environment is destroyed these are harmless, which is a small side benefit of the ephemeral strategy.
- **`.tfvars`** holding anything sensitive — gitignored, with a committed `terraform.tfvars.example`.
- **Personal email** in SNS subscriptions shown in screenshots.

Do not redact the architecture, the IAM policies, or the measurements. Those are the point.

### 18.7 How the CV points at it

- One link on the CV, to the repo root. Not to your GitHub profile — a hiring manager will not go hunting.
- The README's first screenful must repeat the CV bullets' numbers, so the claim and the evidence match on sight. A CV bullet saying "recovered in 2m17s" and a README saying the same thing is a coherent story; a mismatch is worse than saying nothing.
- Link `docs/incidents/` directly in your cover letter or LinkedIn post — it is the most unusual thing in the repo and the most likely to start a conversation.
- Keep the write-up (M14) on LinkedIn or dev.to and link it from the repo, and the repo from it. Two doors into the same work.

### 18.8 Anti-patterns

- **Committing everything at the end.** Destroys the strongest signal you have.
- **A README that reads like a tutorial** ("Step 1: install Terraform"). Nobody is learning from your repo; they are evaluating you.
- **Fabricated or rounded-up metrics.** An interviewer who senses one invented number discounts the entire project, and they will probe.
- **Screenshots with no timestamps or context.** A CloudWatch graph with visible dates is evidence; a cropped one is decoration.
- **Hiding the failures.** Experiment 5 returning 500s because Redis did not fail open is a *better* story than everything working first time — as long as you document the fix. Write up what went wrong; it is the most credible thing in the repo.
- **A private repo.** It cannot prove anything nobody can open.

---

## 19. Immediate next actions

1. Confirm **Free Plan vs Paid Plan** (open item 1) — the only thing that could force an architecture rework.
2. Verify billing has gone flat (+24h / +48h).
3. Claim remaining activity credits if available.
4. Start **M0**: budget guardrails and CloudTrail in the console; `git init`, `.gitignore`, pre-commit and `terraform/bootstrap/` in the repo.

Nothing is built yet. `scripts/aws-inventory.sh`, `scripts/aws-teardown.sh` and `docs/runbooks/account-teardown.md` exist from the cleanup and carry forward into M0.
