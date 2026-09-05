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
| 8 | Milestones M0–M15 |
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
| 021 | Long-lived `cloudforge-admin` access key, kept over IAM Identity Center | Enabling Identity Center requires an AWS Organization, which immediately upgrades the account to Paid Plan and expires all $158 remaining credits | IAM Identity Center / SSO short-lived credentials (better practice, but not at the cost of the entire credit balance) |

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
├── docs/                          # [SCAFFOLDED] — see docs/README.md for the index
│   ├── README.md                 # Navigation hub — what lives where            [BUILT]
│   ├── architecture/              # overview.md — narrative, written once M1–M6 land
│   ├── diagrams/                 # Mermaid, versioned. architecture-high-level.md done [BUILT]
│   ├── infrastructure/           # deployment-strategies.md (rolling vs blue/green)    ★
│   ├── security/                 # threat-model.md, well-architected.md                ★
│   ├── observability/            # slo.md — SLIs, SLOs, error budget policy            ★
│   ├── resilience/               # capacity-planning.md — thresholds derived from load tests ★
│   ├── disaster-recovery/        # strategy.md — backup/restore vs pilot light vs warm standby
│   ├── experiments/              # One report per game day; 000-template.md ready      [BUILT]
│   ├── adr/                      # ADR-001 … ADR-020 — the decision log; 000-template.md ready [BUILT]
│   ├── runbooks/                 # account-teardown.md [BUILT], deploy, rollback, restore, on-call
│   ├── screenshots/              # Evidence by phase, numbered 00-foundations … 15-portfolio-final
│   └── cost-analysis.md          # Real Cost Explorer numbers + optimizations
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

**~19 weeks at 8–10 h/week.** Sept 2026 → roughly Feb 2027, leaving four months of margin before June 2027.

Every milestone below carries three kinds of marker, consistently:
`📝 DECISION RECORD` (write the ADR now), `📐 DIAGRAM CHECKPOINT` (update the visual now), `📸 EVIDENCE REQUIRED` (capture proof now, to the exact path and filename given). Do them at the milestone, not at the end — see §18 for why that's the whole point.

---

### M0 — Foundations · week 1 · 4h

- AWS Budget $20 + alerts at 50/80/100%; CloudWatch billing alarm → SNS → email (**confirm the subscription email**).
- **Cost Anomaly Detection** (free).
- **CloudTrail** — one trail, management events, → S3. First trail per region is free; you get an audit log of every API call for the whole project.
- Root MFA ✅ (done 2026-09-04). **Not** replacing the `cloudforge-admin` access key with IAM Identity Center — enabling it requires creating an AWS Organization, which immediately forces a Paid Plan upgrade and expires all $158 remaining credits. Not worth it for this project; see ADR-021. Keeping the long-lived key with strict hygiene instead (never committed, rotated periodically, deleted at teardown).
- `terraform/bootstrap/` — S3 state bucket: versioned, encrypted, public access blocked, `use_lockfile` in consumers. Local state, applied once, committed, never touched again.
- `git init`, `.gitignore` (`*.tfstate*`, `.terraform/`, `*.tfvars`), `.pre-commit-config.yaml` (fmt, tflint, checkov, terraform-docs, gitleaks).
- Provider `default_tags` shared by both environments.

**DoD:** `terraform init` in an empty env dir reaches the S3 backend and takes a lock.

📝 **DECISION RECORD** — write `docs/adr/001-state-backend.md`, `docs/adr/002-state-isolation.md`, `docs/adr/003-graviton.md`, `docs/adr/012-two-ephemeral-environments.md` and `docs/adr/021-long-lived-key-over-identity-center.md` now, while the reasoning is fresh. Commit each in the same commit as the config it describes.

📸 **EVIDENCE REQUIRED**
Capture:
- AWS Budget configuration (name, amount, alert thresholds)
- Billing alarm + confirmed SNS email subscription
- Cost Anomaly Detection enabled
- Root MFA screen (already done 2026-09-04 — capture retroactively if not already saved)
- `terraform init` output showing a successful S3 backend connection and lock acquired

Save to: `docs/screenshots/00-foundations/`
Suggested files: `budget-config.png`, `billing-alarm.png`, `anomaly-detection.png`, `root-mfa.png`, `terraform-init-backend.png`

Purpose: proves the cost guardrails existed *before* any billable resource was created — this is the safety-net story, and it only works if the timestamps predate M1.

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

📝 **DECISION RECORD** — `docs/adr/005-ssm-session-manager.md`, `docs/adr/008-nat-strategy.md`, `docs/adr/016-terraform-native-tests.md` (first `.tftest.hcl`).

📐 **DIAGRAM CHECKPOINT** — replace the target-state diagram with the as-built one: `docs/diagrams/network-vpc.md`, showing the real VPC ID, subnet CIDRs and route tables from this apply (Mermaid, not another ASCII block).

📸 **EVIDENCE REQUIRED**
Capture:
- VPC resource map (the console's Resource Map view — shows all subnets/AZs at a glance)
- Public and private route tables, side by side
- NAT Gateway or NAT instance detail
- VPC Flow Logs enabled, showing a log group with entries
- Terminal recording: SSM Session Manager session into a private-subnet instance
- `terraform apply` output for the network module

Save to: `docs/screenshots/01-networking/`
Suggested files: `vpc-resource-map.png`, `route-tables-public.png`, `route-tables-private.png`, `nat-gateway.png`, `flow-logs.png`, `ssm-session-private-instance.png`, `terraform-apply-network.png`

Purpose: proof the multi-AZ, three-tier network was actually deployed, and that a private instance is reachable with no SSH key anywhere in existence.

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

📸 **EVIDENCE REQUIRED — minimal, this milestone is scaffolding, not the point of the project**
Capture:
- `docker-compose up` with Postgres, Redis and LocalStack all healthy
- `go test ./...` passing output
- `go build` cross-compiled arm64 binary — file listing showing its size (~12 MB)

Save to: `docs/screenshots/02-application/`
Suggested files: `docker-compose-up.png`, `go-test-pass.png`, `arm64-binary-size.png`

Purpose: minimal on purpose. Say plainly in the README that the app is a deliberately trivial prop — don't over-document it here either.

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

📝 **DECISION RECORD** — `docs/adr/004-go-binary-artifact.md`, `docs/adr/007-target-tracking-scaling.md`.

📸 **EVIDENCE REQUIRED**
Capture:
- Launch Template configuration (AMI, instance type, IAM instance profile, user-data)
- Auto Scaling Group detail page — min/desired/max, and instances across both AZs
- EC2 instances list showing 2 instances, one per AZ
- The IAM role's policy document (JSON) — proof of hand-written least privilege, no `Resource: "*"`
- Before/after of a manual termination: the terminated instance, then the replacement healthy in the target group

Save to: `docs/screenshots/03-compute/`
Suggested files: `launch-template.png`, `asg-detail.png`, `ec2-instances-multi-az.png`, `iam-role-policy.png`, `instance-replacement-before.png`, `instance-replacement-after.png`

Purpose: proof of self-healing compute and least-privilege IAM — two of the project's core claims. Also write the IAM policy walkthrough into `docs/security/README.md` now, while you can still explain each permission's reason.

⏱️ **Rough measurement now, refined properly in M12:** note how long the replacement took to appear and go healthy. Don't build a full experiment file yet — just a line in your notes to compare against the real FIS-driven number later.

---

### M4 — Load balancing, edge TLS, WAF · weeks 5–6 · 10h

- ALB in public subnets. **Two target groups** (blue and green) for M8's blue/green. Shallow `/healthz` check, 10s interval, 2/2 thresholds, 30s deregistration delay. Access logs → S3.
- CloudFront distribution, `/api/*` behavior, caching disabled on that path. **HTTPS free** (ADR-011).
- **AWS WAF** on the distribution with AWS managed rule groups (`CommonRuleSet`, `KnownBadInputs`, `AmazonIpReputationList`) plus a rate-based rule. ~$7/month, pennies per game day.
- SG chain, explicitly: `CloudFront prefix list → ALB:80` · `ALB-SG → App-SG:8080` · `App-SG → RDS-SG:5432` · `App-SG → Redis-SG:6379`. **Nothing permits `0.0.0.0/0`.** ALB additionally requires the secret origin header (ADR-014).
- Route 53 **private** hosted zone: `db.cloudforge.internal`, `cache.cloudforge.internal`.

**DoD:** `curl https://<dist>.cloudfront.net/api/whoami` returns alternating instance IDs with a valid cert, while `curl http://<alb-dns>/...` fails.

📝 **DECISION RECORD** — `docs/adr/006-shallow-health-check.md`, `docs/adr/010-cloudfront-two-origins.md`, `docs/adr/011-no-custom-domain.md`, `docs/adr/013-private-hosted-zone.md`, `docs/adr/014-alb-locked-to-cloudfront.md`.

📐 **DIAGRAM CHECKPOINT** — `docs/diagrams/traffic-flow.md`: CDN → WAF → origin routing, with the ALB lockdown mechanism shown explicitly (this is the interesting part, don't just draw arrows).

📸 **EVIDENCE REQUIRED**
Capture:
- ALB target group health — both targets healthy, one per AZ
- CloudFront distribution config showing both origins (S3 + ALB)
- SSL Labs report for the CloudFront hostname
- WAF web ACL rules list
- **A deliberate SQL-injection attempt** (`curl ".../api/products?id=' OR 1=1--"`) blocked — screenshot the 403 response AND the WAF sampled-requests log entry
- `curl` side-by-side: CloudFront URL succeeds, direct ALB DNS name fails/times out

Save to: `docs/screenshots/04-load-balancing/`
Suggested files: `alb-target-health.png`, `cloudfront-origins.png`, `ssl-labs-report.png`, `waf-rules.png`, `waf-blocked-sqli.png`, `alb-direct-access-blocked.png`

Purpose: the security-perimeter story — CDN, WAF and origin lockdown working together. The WAF-blocked screenshot is one of the strongest single artifacts in the whole repo; don't skip it.

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

📝 **DECISION RECORD** — `docs/adr/009-secrets-manager-rds-password.md`, `docs/adr/015-snapshot-lifecycle.md`.

📸 **EVIDENCE REQUIRED**
Capture:
- RDS instance configuration — Multi-AZ toggle visibly on, encryption, subnet group
- Secrets Manager secret metadata showing rotation configured (**never** the secret value)
- Security group rules showing RDS accepts connections only from the App security group
- Terminal capture: `psql` connection attempt from the open internet, refused
- Terminal capture: successful `psql` session reached via an SSM-tunneled instance

Save to: `docs/screenshots/05-database/`
Suggested files: `rds-config-multiaz.png`, `secrets-manager-rotation.png`, `rds-security-group.png`, `rds-connection-refused-internet.png`, `rds-psql-via-ssm.png`

Purpose: Multi-AZ resilience and network isolation for the data tier. Double-check every screenshot before saving — never capture a secret's actual value, only its metadata.

---

### M6 — Cache, storage, CDN · weeks 7–8 · 10h

**ElastiCache Redis** — data subnets, encryption in transit and at rest, AUTH token in Secrets Manager, `cache.t4g.micro`. Cache-aside, TTL 60s, invalidate on write, fails open.
> Measure: p95 latency cold vs warm, RDS `DatabaseConnections` before/after. A cache without a measurement is decoration.

**S3** — `images` (versioned, CDN origin), `artifacts` (versioned), `logs` (lifecycle → Glacier IR → expire). All: public access blocked, SSE, TLS-only bucket policy.

**CloudFront** — add the `/images/*` behavior with **OAC**, long TTL, compression. One distribution, two origins, two cache policies (ADR-010).

**DoD:** image serves from the CDN; direct S3 URL returns 403.

📐 **DIAGRAM CHECKPOINT** — `docs/diagrams/data-flow.md`: the cache-aside read path (client → CloudFront → ALB → app → Redis → RDS on miss) and the S3 image-upload path, as two clearly separate flows in one diagram.

📸 **EVIDENCE REQUIRED**
Capture:
- ElastiCache Redis cluster configuration
- All three S3 bucket policies, showing "public access blocked" confirmed on each
- CloudFront cache behaviors — both `/images/*` and `/api/*`, showing their differing TTLs
- Cache hit-ratio graph after generating some real traffic
- Side-by-side: direct S3 object URL returns 403, the same object via CloudFront returns 200

Save to: `docs/screenshots/06-cache-storage-cdn/`
Suggested files: `elasticache-config.png`, `s3-bucket-policies.png`, `cloudfront-behaviors.png`, `cache-hit-ratio.png`, `s3-403-vs-cloudfront-200.png`

Purpose: demonstrates OAC actually keeps the bucket private, and that the cache is measurably doing something — not just present. Record the p95 latency cold-vs-warm numbers from PLAN.md's cache note directly into this milestone's notes; they feed the measurements table in §11.

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

📝 **DECISION RECORD** — `docs/adr/020-slos-before-gamedays.md`. Also write `docs/observability/slo.md` in full now (SLIs, SLOs, error-budget policy from PLAN.md §10) — this is the document every M12 experiment measures itself against, so it must exist before M12 starts, not after.

📸 **EVIDENCE REQUIRED**
Capture:
- The Four Golden Signals dashboard (full view — latency, traffic, errors, saturation)
- The SLO dashboard
- The alarms list (grid view, all configured alarms visible at once)
- One deliberately triggered alarm, plus the resulting email
- Synthetics canary results over time (a few hours minimum)
- A CloudWatch Logs Insights query result showing structured JSON logs

Save to: `docs/screenshots/07-observability/`
Suggested files: `golden-signals-dashboard.png`, `slo-dashboard.png`, `alarms-list.png`, `alarm-triggered-email.png`, `synthetics-canary-results.png`, `logs-insights-query.png`

Purpose: the Golden Signals dashboard is very likely the README's hero image — spend real time getting it right before screenshotting it. Also write one runbook per alarm into `docs/runbooks/` now, while you remember what each one is actually for.

---

### M8 — CI/CD, testing, drift detection · weeks 10–11 · 12h ★

**`terraform.yml`** — PR: `fmt -check` → `validate` → `tflint` → `checkov` → **`terraform test`** → `plan` as a PR comment → `infracost diff`. Merge to `main`: auto-apply dev; prod behind manual environment approval.

**`app.yml`** — `go test` → `go vet` → `govulncheck` → cross-compile arm64 → upload to versioned S3 key → new LT version → `start-instance-refresh` → poll.

**`drift.yml`** ★ — scheduled daily `terraform plan -detailed-exitcode`; non-empty plan → GitHub issue + SNS. *"I detect manual console changes automatically"* is a real operations answer almost no portfolio has.

**`nightly-destroy.yml`** ★ — `terraform destroy` on dev at 23:00, backstop for the night you forget.

- **GitHub OIDC to AWS**, trust policy scoped to your repo *and* branch. No static keys anywhere. Document the trust policy in `docs/security/` — "how does your CI authenticate to AWS" is a near-guaranteed interview question.
- **Blue/green deployment** ★ as a second strategy: two target groups, ALB listener weight shift 100/0 → 0/100, with a soak window and one-command rollback.
- **k6 in CI with thresholds** as a performance regression gate.

**DoD:** a one-line change reaches prod with zero downtime via both strategies.

📝 **DECISION RECORD** — `docs/adr/017-bluegreen-second-strategy.md`.

📸 **EVIDENCE REQUIRED**
Capture:
- GitHub Actions run: `terraform plan` posted as a PR comment
- GitHub Actions run: the full `app.yml` pipeline green (test → build → upload → refresh)
- ASG Instance Refresh detail page in the console (progress bar / activity history)
- k6 output showing **0 failed requests** during the rolling refresh
- ALB listener rules before/after a blue/green weight shift (100/0 → 0/100)
- A deliberate console change triggering the `drift.yml` GitHub issue

Save to: `docs/screenshots/08-cicd/`
Suggested files: `pr-plan-comment.png`, `app-pipeline-green.png`, `instance-refresh-progress.png`, `k6-zero-failed-refresh.png`, `bluegreen-weight-shift.png`, `drift-detected-issue.png`

Purpose: this is the single strongest technical claim in the whole project — zero-downtime deploy with no orchestrator, done two ways. Document it thoroughly. Record pipeline duration and refresh duration into `docs/infrastructure/deployment-strategies.md`, comparing rolling vs. blue/green with the real numbers side by side — not estimates.

⏱️ **Feeds:** `docs/experiments/06-rolling-deploy.md` and `docs/experiments/07-bluegreen-deploy.md` in M12 reuse these exact measurements under load; capture the k6 raw output now so you don't have to rerun it later.

---

### M9 — Environments, module hardening, public module · week 12 · 8h

- Every hardcoded value → module variable with defaults and `validation` blocks.
- `dev` vs `prod` tfvars differ **only** in: sizes, counts, `multi_az`, `nat_type`, retention, deletion protection.
- `terraform-docs`-generated README per module.
- `.tftest.hcl` coverage for every module (ADR-016).
- ★ **Publish one module to the public Terraform Registry** — repo named `terraform-aws-<name>`, semver tags. A public URL a recruiter can click, with a download count. Free, and very few juniors have one.

**DoD:** both environments apply from identical module code; `terraform test` green across all modules.

📸 **EVIDENCE REQUIRED**
Capture:
- `terraform test` output, all green, across every module
- Side-by-side `dev` vs `prod` `terraform.tfvars` diff
- The published module's Terraform Registry page

Save to: `docs/screenshots/09-modules/`
Suggested files: `terraform-test-all-green.png`, `dev-vs-prod-tfvars-diff.png`, `terraform-registry-module-page.png`

Purpose: proof of module reuse and test coverage — "two consumers, one module set," backed by a public, clickable Registry URL.

---

### M10 — Security hardening and Well-Architected review · week 13 · 10h ★

- **AWS Well-Architected Tool** (free, in console) — run a formal review of the workload against all six pillars. Record every finding, remediate what you can, and document what you consciously accepted and why.
  > *"I ran a Well-Architected review against my own architecture and remediated 14 of 19 findings; the remaining 5 are documented accepted risks with rationale"* is an exceptionally strong sentence, and almost nobody at your stage has it.
- **GuardDuty** enabled during its 30-day trial window; document findings; disable before it bills.
- **Checkov custom policy** — e.g. "no security group may allow `0.0.0.0/0` on port 22", "every S3 bucket must block public access", "all resources must carry the required tags". Enforced in CI.
- **Threat model** in `docs/security/threat-model.md`: what an attacker would try, what stops them at each layer, what you consciously did not defend against.
- **Encryption inventory**: every data store, at rest and in transit, with the key type.
- **IAM Access Analyzer** — free; check for unintended external access.

**DoD:** Well-Architected review complete; all high-severity findings either fixed or documented as accepted.

📐 **DIAGRAM CHECKPOINT** — `docs/diagrams/security-flow.md`: WAF, security-group chain, and IAM boundaries as one connected picture, matching what the threat model in `docs/security/threat-model.md` actually describes.

📸 **EVIDENCE REQUIRED**
Capture:
- AWS Well-Architected Tool review summary — all six pillars, finding counts
- GuardDuty findings dashboard
- IAM Access Analyzer results
- A deliberately bad PR failing the custom Checkov policy in CI

Save to: `docs/screenshots/10-security/`
Suggested files: `well-architected-summary.png`, `guardduty-findings.png`, `access-analyzer-results.png`, `checkov-custom-policy-fail.png`

Purpose: the formal review artifact — a strong, uncommon addition to a junior portfolio. Write `docs/security/well-architected.md` documenting every finding and its remediation or accepted-risk rationale; write `docs/security/threat-model.md` and `docs/security/encryption-inventory.md` in the same pass.

---

### M11 — Backup and DR automation · week 14 · 10h ★

- **AWS Backup**: vault, backup plan, RDS + EBS selection by tag, retention, lifecycle to cold storage, **cross-region copy** to a second region. Snapshot-cost only, and it turns DR from a paragraph into a configuration.
- **SSM Automation runbooks** ★ — executable recovery, not prose. E.g. a document that restores the latest RDS snapshot into a new instance, updates the private-zone DNS record, and verifies connectivity. *"My runbooks are executable"* beats *"I wrote a runbook."*
- **`restore-test.yml`** ★ — scheduled weekly: restore the latest snapshot into a temporary instance, run a data-integrity check, record the restore duration, destroy it. **Automated backup verification is something most production teams do not do**, and it produces a recurring measurement.
- **DR strategy comparison** in `docs/disaster-recovery/strategy.md`: backup/restore vs pilot light vs warm standby vs active-active — cost, RPO and RTO for each, which you chose and why. Shows you know the options, not just the one you built.

**DoD:** the restore drill runs unattended and reports a duration.

📝 **DECISION RECORD** — `docs/adr/018-aws-backup-over-native.md`, `docs/adr/019-fis-over-manual-chaos.md`.

📐 **DIAGRAM CHECKPOINT** — `docs/diagrams/dr-recovery-flow.md`: the restore path from a snapshot in the cross-region vault back to a serving instance, with the SSM Automation steps shown as the actual sequence they execute.

📸 **EVIDENCE REQUIRED**
Capture:
- AWS Backup vault + plan configuration, including the cross-region copy destination
- SSM Automation document — one successful execution log, end to end
- `restore-test.yml` workflow run history — several green runs across different weeks, not just one
- The restored RDS instance passing its data-integrity check

Save to: `docs/screenshots/11-backup-dr/`
Suggested files: `backup-vault-plan.png`, `ssm-automation-execution.png`, `restore-test-workflow-history.png`, `restore-integrity-check-pass.png`

Purpose: "my backups are verified weekly" needs a paper trail, not just a claim — the workflow history screenshot across multiple weeks is what actually proves that.

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

⏱️ **MEASUREMENT REQUIRED — for every one of the 10 experiments**, filed as `docs/experiments/NN-<name>.md` (copy `docs/experiments/000-template.md`). Never invent a number here — an unmeasured field left honestly blank outranks a plausible invented one. Each file must record:
- Time the fault was introduced (UTC)
- Detection time (first alarm / metric change)
- Recovery action start time
- Service restoration time
- Total requests during the window / failed requests / error rate
- Error budget consumed (%, against `docs/observability/slo.md`)
- Final steady-state confirmation
- What surprised you
- What you changed as a result

📸 **EVIDENCE REQUIRED — per experiment**, capture:
- Timestamped terminal output of the fault-injection command (the FIS experiment start, or the CLI invocation used)
- CloudWatch metrics graph spanning the whole incident window — before, during and after
- ALB target health transitioning unhealthy → healthy
- k6 live output during the experiment
- Final "back to steady state" confirmation

Save to: `docs/screenshots/12-gamedays/<NN-experiment-name>/`
Suggested files: `fis-experiment-start.png`, `metrics-during-incident.png`, `target-health-transition.png`, `k6-live-output.png`, `steady-state-restored.png`

Purpose: this is the core evidence of the entire project. Every number in the §11 measurements table must trace back to a screenshot and an experiment file here.

🎥 **GIF/VIDEO CANDIDATE** — flag experiments **#1** (EC2 failure → replacement), **#3** (load → auto scaling), **#4** (RDS failover) and **#9** (full rebuild) as prime screen-recording material. Record the terminal and a relevant console tab simultaneously if you can; these four are the strongest candidates for the M15 demo reel.

**Evidence (roll-up):** `docs/experiments/01…10.md`, each a postmortem with timeline, graphs, error-budget impact, and resulting changes — this replaces the old `docs/incidents/` naming; the folder is `docs/experiments/`.

---

### M13 — DR validation and capacity planning · week 17 · 8h

- State RPO/RTO targets *before* testing, then report actual vs target — **including where you missed**. A missed target you diagnosed is more credible than a perfect scorecard.
- Honest data-loss analysis: what is recoverable, what is not (in-flight requests, cache), why that is acceptable.
- ★ **`docs/resilience/capacity-planning.md`** — from the load tests: max sustainable RPS per instance, the saturation point, where the bottleneck moved (app → DB → cache), and the scaling thresholds *derived from those numbers* rather than guessed. This is the difference between "I set CPU at 70%" and "I set it at 70% because throughput degrades non-linearly past 74%."
- Error-budget report for the game-day period (§10).

📸 **EVIDENCE REQUIRED**
Capture:
- The cross-region restore execution and its timing
- The capacity-planning graph (RPS vs. latency, with the saturation point marked)
- The RPO/RTO actual-vs-target table, alongside the raw CloudWatch graph it was derived from

Save to: `docs/screenshots/13-dr-validation/`
Suggested files: `cross-region-restore.png`, `capacity-planning-graph.png`, `saturation-point-graph.png`

Purpose: ties the resilience narrative to concrete, derived numbers rather than guessed thresholds. A missed RPO/RTO target that you diagnosed here is more credible than a perfect scorecard — write that up honestly in `docs/disaster-recovery/strategy.md`.

---

### M14 — Cost analysis, polish, publication · week 18 · 10h

- **Cost:** Cost Explorer by tag for the real period. Document each optimization (Graviton, NAT instance, S3 gateway endpoint, lifecycle policies, ephemeral environments) with before/after numbers. Baseline is already captured: **$0.77/day before teardown, $0.00/day after** (§16).
- **README** — written last, for a recruiter reading for 90 seconds. Architecture diagram in the first screenful, then the measurements table, then depth below the fold.
- **Architecture diagram** — draw.io or Excalidraw, exported PNG. ASCII in the terminal; a real image in the README.
- ★ **Screen recording, 3–5 minutes**: apply → curl → FIS kills an instance → dashboard reacts → self-heals. This outperforms every screenshot you will ever take.
- ★ **Write-up** — a blog post or LinkedIn article series on the game-day results and what surprised you. Free, findable by recruiters, and forces you to articulate the project the way you will in an interview. The "what surprised me" fields from M12 are the draft.
- Repo polish: LICENSE, badges, a `docs/` index, and pinned issues showing planned work.

📸 **EVIDENCE REQUIRED**
Capture:
- Cost Explorer grouped by tag, for the full project period
- Before/after cost comparison — the account-cleanup baseline (§16, ~$0.77/day) vs. the optimized ephemeral run rate
- The final README as it actually renders on GitHub

Save to: `docs/screenshots/14-final/`
Suggested files: `cost-explorer-by-tag.png`, `before-after-cost.png`, `readme-rendered-github.png`

Purpose: closes the cost narrative with real Cost Explorer numbers, not estimates.

---

### M15 — Documentation and portfolio finalization · week 19 · 10h

The last mile. Nothing here is new engineering — it's making sure everything built in M0–M14 is actually *visible* to someone who didn't build it.

- **Finalize `README.md`** as the technical case study (§18.5) — every section filled, every `__` placeholder in the CV bullets (§14) and measurements table (§11) replaced with a real number, nothing left saying "not yet."
- **Confirm every diagram is current**: `docs/diagrams/architecture-high-level.md`, `network-vpc.md`, `traffic-flow.md`, `security-flow.md`, `data-flow.md`, `dr-recovery-flow.md` — six diagrams, all matching what was actually built, not what was planned.
- **Confirm every `docs/` subfolder has real content**, not the stub READMEs created during planning. A folder that still says "not written yet" at this point is an unfinished milestone, not a finished one.
- **Compile the GIF/video candidates** flagged through M0–M13 into an actual 3–5 minute demo reel: `terraform apply` → `curl` → FIS kills an instance → dashboard reacts → self-heals.
- **Write the public write-up** (blog post or LinkedIn article) on the game-day results and what surprised you — the "what surprised me" fields from every `docs/experiments/*.md` file are the draft.
- **Cross-check the CV bullets (§14)** against the actual measured numbers in §11 line by line.
- **Final repo polish**: LICENSE, GitHub topics/tags for discoverability, pinned repo on your profile, Actions badges in the README, a GitHub Projects board showing M0–M15 progress.
- **Cold-read pass**: read the README as a recruiter would, with a 90-second budget. Does it work in that time?

**DoD:** the portfolio artifacts checklist (§12) is fully ticked, with no placeholders left anywhere in the repo.

📸 **EVIDENCE REQUIRED**
Capture:
- The final GitHub repo homepage (README render, topics, description)
- GitHub Insights → commit activity graph, showing sustained work spread across the project, not a single dump

Save to: `docs/screenshots/15-portfolio-final/`
Suggested files: `github-repo-homepage.png`, `commit-activity-graph.png`

Purpose: the commit history and repo presentation are themselves evidence — a hiring manager checks both, and this is the checkpoint where you verify they hold up.

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
- [ ] Six diagrams in `docs/diagrams/` — architecture, network, traffic-flow, security-flow, data-flow, DR-flow — all Mermaid, all matching what was actually built
- [ ] 20 ADRs in `docs/adr/`
- [ ] 10 experiment reports in `docs/experiments/` with timelines and resulting changes
- [ ] `docs/security/well-architected.md` with findings and remediations
- [ ] `docs/observability/slo.md` with the error-budget report
- [ ] `docs/infrastructure/deployment-strategies.md` with measured comparison
- [ ] `docs/resilience/capacity-planning.md` with graphs
- [ ] `docs/disaster-recovery/strategy.md` with tested RPO/RTO
- [ ] `docs/cost-analysis.md` with before/after numbers
- [ ] `docs/security/threat-model.md` with the IAM walkthrough
- [ ] Runbook per alarm, plus executable SSM Automation runbooks
- [ ] One module published to the Terraform Registry
- [ ] Green CI with tests, security scanning and drift detection
- [ ] A public write-up
- [ ] Six CV bullets with real numbers (§14), matching §11 exactly
- [ ] Every `docs/screenshots/*` phase folder populated — nothing skipped

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
| 8 | Free Plan vs Paid Plan | ✅ **Staying on Free Plan.** Confirmed 2026-09-05 the account is on the Free Plan. Decided *not* to upgrade — evidence shows this doesn't restrict service selection: the Pitstop EKS cluster already ran NAT Gateways, EKS and load balancers (none free-tier-eligible) on this same account under this same plan and billed normally against credits. The Free Plan is a spend-cap/auto-suspend safety net, not a service allow-list. **No rework needed for M1/M4/M6.** M0's own Budget + billing alarm are the operative guardrail regardless of AWS's internal threshold. |
| 9 | Remaining activity credits | ✅ **None hidden.** Credits page confirms exactly $100 signup + 3×$20 Explore AWS = $160 total, matching §16 exactly — the "~$40 more" note below was a pre-verification guess, now resolved. |
| 10 | Public repo | ✅ **Public**, already pushed to `github.com/Mouad852/cloudforge`. Redaction discipline (§18.6) applies from the first commit onward, not as a later pass. |

**Open:**

1. **`[PENDING]` Credit service coverage.** Each credit row has a *"See complete list of services"* link. Confirm the $100 credit covers NAT Gateway and data transfer specifically — two of the four largest line items in §4. Low priority given decision #8 above.
2. **`[PENDING]` Billing verification.** Bills at +24h, Credits at +48h (§16).

---

## 18. Documentation and proof of work

**Scaffolding for everything in this section already exists** — `docs/README.md` and every subfolder's README, `docs/adr/000-template.md`, `docs/experiments/000-template.md`, and the first diagram (`docs/diagrams/architecture-high-level.md`) were built ahead of M0 specifically so the milestone markers below have somewhere real to point. Nothing in them is filled in yet; that happens milestone by milestone, per the `📸 EVIDENCE REQUIRED` blocks now embedded in §8.

### 18.1 The problem this section solves

Anyone can now generate a repository full of plausible Terraform in an afternoon. A hiring manager knows that. So the question is not *"does this repo contain good infrastructure code?"* — it is **"did this person actually do this, and do they understand it?"**

Everything below is designed to answer that second question. The repo is not documentation of the work; **the repo is the evidence.**

### 18.2 What actually convinces, ranked

| Rank | Signal | Why it is hard to fake |
|---|---|---|
| 1 | **Commit history spread across months** | A repo with ~250 commits between Sept and Feb reads completely differently from one with 4 commits on a single day. The commit graph is the first thing an engineer checks, and a project dumped in one push looks bought or generated. This is the single strongest signal and it costs you nothing except committing as you go. |
| 2 | **The 3–5 minute screen recording** | A real terminal and a real console showing a real instance dying and the system healing. Nearly impossible to fabricate convincingly. |
| 3 | **Experiment reports with real timestamps and graphs** (`docs/experiments/`) | CloudWatch graphs carry real dates and real shapes. The "what surprised me" field especially — genuine surprise reads differently from invented surprise. |
| 4 | **ADRs committed on the day the decision was made** (`docs/adr/`) | A dated decision log is a timeline of your thinking. Twenty ADRs added in one commit at the end proves nothing; twenty committed across five months proves everything. |
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
- **GitHub Pages** serving `docs/` — free, and makes the experiment reports and ADRs browsable rather than requiring a clone.
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

## Architecture      → docs/architecture/, docs/diagrams/
## Decisions (20 ADRs) → docs/adr/
## Failure experiments → docs/experiments/
## SLOs & error budget → docs/observability/slo.md
## Security & Well-Architected review → docs/security/
## Disaster recovery   → docs/disaster-recovery/
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
- Link `docs/experiments/` directly in your cover letter or LinkedIn post — it is the most unusual thing in the repo and the most likely to start a conversation.
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

1. Finish **M0**: budget guardrails and CloudTrail in the console; `terraform/bootstrap/` in the repo.
2. Verify billing has gone flat (+24h / +48h) — open item 2 in §17.

**What's already built, ahead of schedule:**
- Repo initialized, first commit pushed, pre-commit hooks (gitleaks, fmt/validate/tflint/checkov, terraform-docs) installed and passing
- `scripts/aws-inventory.sh`, `scripts/aws-teardown.sh`, `docs/runbooks/account-teardown.md` — from the account cleanup, carry forward into M0
- The full `docs/` documentation scaffold (§7, §18): every subfolder's README, the ADR and experiment templates, and the first architecture diagram

No Terraform, no application code, and no AWS resources beyond the account guardrails exist yet. Everything else is scaffolding for evidence that doesn't exist to capture yet.
