# Well-Architected review

**Workload:** `CloudForge` in the AWS Well-Architected Tool (eu-west-3), AWS Well-Architected
Framework lens. **Reviewed:** 2026-09-27. A baseline was saved before remediation, and the
answers were reviewed again on 2026-10-03 after the corresponding controls were deployed.

![Well-Architected summary](../screenshots/10-security/well-architected-summary.png)

## Baseline

| Pillar | Questions | High risk | Medium risk | No risk |
|---|---|---|---|---|
| Operational Excellence | 11 | 4 | 4 | 3 |
| Security | 11 | 8 | 0 | 3 |
| Reliability | 13 | 5 | 4 | 4 |
| Performance Efficiency | 5 | 0 | 5 | 0 |
| Cost Optimization | 11 | 5 | 4 | 2 |
| Sustainability | 6 | 0 | 6 | 0 |
| **Total** | **57** | **22** | **23** | **12** |

## Remediation result

**Six of 22 high risks were remediated.** The answers were updated only after each control was
deployed to prod and checked there. Remaining risks are recorded as accepted constraints or
documented limitations.

| Pillar | High risk | Medium risk | No risk |
|---|---|---|---|
| Operational Excellence | 4 → 2 | 4 → 5 | 3 → 4 |
| Security | 8 → 6 | 0 → 2 | 3 → 3 |
| Reliability | 5 → 3 | 4 → 6 | 4 → 4 |
| Performance Efficiency | 0 → 0 | 5 → 5 | 0 → 0 |
| Cost Optimization | 5 → 5 | 4 → 4 | 2 → 2 |
| Sustainability | 0 → 0 | 6 → 6 | 0 → 0 |
| **Total** | **22 → 16** | **23 → 28** | **12 → 13** |

| Question | Now | What moved it | Why it is not lower |
|---|---|---|---|
| OPS 10 - workload and operations events | High → none | Incident process with severities tied to the SLOs, used for the 2026-09-30 outage | - |
| OPS 7 - ready to support | High → medium | Readiness checklist, investigation playbooks | Basic support plan |
| SEC 7 - data classification | High → medium | `data-classification.md`, a retention for every store | Classification is manual (no Macie) |
| SEC 10 - incidents | High → medium | `incident-response.md`: response process, access prepared in advance, playbooks | Forensics stops at EBS snapshots |
| REL 5 - mitigate interaction failures | High → medium | Request deadline, server, Redis and Postgres timeouts, bounded retries | No emergency levers beyond the WAF |
| REL 8 - implement change | High → medium | `docs/runbooks/deployment.md` | Resiliency testing is a controlled operational exercise, not a CI stage |

Twelve other answers changed only their notes, so their risk stayed the same. They now describe
EBS encryption by default, CloudTrail retention, cost allocation tags, the budget
measured before credits, the canary-failed alarm and the first post-incident review. They also
correct four notes that had gone stale: how the app reaches prod, how a deploy rolls back, the
Free plan's 1-day backup cap, and govulncheck.

## How the questions were answered

Every answer was checked against what is actually deployed: the Terraform in this repository,
the ADRs, and the account itself (root MFA, IAM users and keys, CloudTrail, Access Analyzer
findings). Each question carries a note in the tool saying what the workload does and naming
what it does not. A practice was ticked only if it is in place today, not if it is planned.

**21 best practices are marked "not applicable"**, each with its reason recorded in the tool.
Only practices that cannot apply to this workload were marked, for four reasons: it is a
one-person project (no teams, escalation chain or finance partner), it has a single VPC (nothing
to peer or overlap), there is no on-premises network, and the account is not in an AWS
Organization. A practice the workload *could* adopt but doesn't stays a gap, even when a
constraint explains it. The first pass, without these, scored 30 high risks. The 8 it removed
were practices that cannot exist here, not problems.

## High-risk findings

Every high-risk question is listed with the practices it is missing and an outcome: remediated,
accepted with a reason, or documented as a limitation.

### Remediated controls

| Question | Missing | Remediation |
|---|---|---|
| SEC 7 - How do you classify your data? | No classification scheme, no controls tied to sensitivity, no lifecycle definition | [Data classification](data-classification.md) defines each store's sensitivity, controls, and retention. |
| SEC 10 - How do you anticipate, respond to, and recover from incidents? | Incident management process and security playbooks | [Incident response](incident-response.md) defines severity, access, evidence sources, and response procedures. |
| OPS 10 - How do you manage workload and operations events? | Incident/problem process; prioritisation by business impact | Severity levels are tied to the SLOs in `docs/observability/slo.md`. |
| OPS 7 - How do you know that you are ready to support a workload? | Operational readiness review, investigation playbooks, support plan | An operational readiness checklist gates prod changes; investigation playbooks and a Basic support plan are in place. |
| REL 8 - How do you implement change? | Deployment and rollback procedure | [Deployment runbook](../runbooks/deployment.md) covers rolling deployment, blue/green routing, failure handling, and rollback. |

Also remediated, although the question stays high risk because of the accepted Multi-AZ gap
(REL 10): **prod's CI-deployed settings**. Deletion protection (database and ALB), 30-day log
retention and deferred database changes (`apply_immediately = false`) existed only in a local,
gitignored `terraform.tfvars` that CI never reads, so the prod that CI deploys ran without them.
They are now the defaults of `terraform/environments/prod`. The same file asked for 7-day
backups, but applying that failed: **the AWS Free plan caps RDS automated backups at 1 day**
(`FreeTierRestrictionError`, 2026-09-27), so prod keeps 1 day and longer recovery points are
outside the platform's current recovery boundary.

### Evaluated controls

| Question | Missing | Outcome |
|---|---|---|
| REL 5 - How do you mitigate interaction failures? | Retry limits, fail fast, client timeouts, emergency levers | **Fixed** (commit eeb2ddb, deployed to prod 2026-10-01). The audit found no deadline on any request: handlers used a context that only ends when the client disconnects, so a hung Postgres held each request, and one of the pool's 4 connections, until the ALB's 60-second timeout. The Redis "fail open" was slow: go-redis's defaults held each call for 5 seconds against a Redis that stopped answering, and ignored the request's deadline (both measured in `app/timeouts_test.go`). pgx had no connect timeout and `net/http` no server timeouts. Now: a 10-second deadline on every request, server timeouts with `IdleTimeout` above the ALB's idle timeout (so the ALB never reuses a connection the app just closed), Redis calls that give up after 250 ms with one retry, and a 5-second Postgres connect timeout. Emergency levers stay as they are: the WAF rate limit. |
| REL 4 - How do you prevent interaction failures? | Loose coupling, idempotent mutations, constant work | **Accepted, not built.** A retried `POST /api/products` creates a duplicate. Nothing retries it today: the canary only reads, the deploy gate only calls `/readyz`, and there is no client SDK. If an automatic client is added, the design is an `Idempotency-Key` header stored with a unique constraint in the same transaction as the product. |
| OPS 4 - How do you implement observability? | Distributed tracing | **Accepted, not built.** One service with two dependencies: every request already logs its ID, status and duration, and now the cause of every 5xx; ALB metrics, the canary and RDS Performance Insights cover the rest. X-Ray would add an agent, IAM permissions and SDK instrumentation for little new information. Revisit if a second service appears. |

### Accepted

| Question | Missing | Why it is accepted |
|---|---|---|
| SEC 1 - How do you securely operate your workload? | Separate accounts for dev and prod; security services | Separate accounts need AWS Organizations, which moves the account off the Free plan and forfeits its remaining credit (ADR-021). GuardDuty, Security Hub and Inspector are unavailable on the Free plan (checked 2026-09-27: `SubscriptionRequiredException`). Partly compensated: IAM Access Analyzer (0 active findings), Checkov with two custom policies in CI, daily drift detection, CloudTrail in all Regions, a budget measured before credits. |
| SEC 2 - How do you manage identities? | Strong sign-in and temporary credentials for the one human identity; central identity provider; rotation | ADR-021: IAM Identity Center requires an Organization (same forfeit). The admin user `cloudforge-admin` has a long-lived access key and no console password; root has MFA and no access keys. Every machine identity (CI, EC2) already uses temporary credentials. |
| SEC 3 - How do you manage permissions? | Least privilege for the CI apply role and the admin user; guardrails; lifecycle; emergency access | The apply role is `PowerUserAccess` plus a hand-scoped IAM policy; writing a least-privilege policy for everything Terraform manages is a large effort for a one-person project. No SCPs without an Organization. Root with MFA is the break-glass identity. |
| SEC 6 - How do you protect your compute resources? | Vulnerability scanning, hardened images, signed artifacts | Inspector needs the paid plan. Instances are immutable and launch from the newest Amazon Linux 2023 AMI; dev on every rebuild after the nightly destroy, prod on every deploy. No SSH (SSM only), IMDSv2 required. |
| SEC 9 - How do you protect your data in transit? | TLS from clients to the ALB | ADR-025: AWS Support denied CloudFront to this account, and an ACM certificate needs a custom domain, rejected on cost (ADR-011). Everything behind the ALB is encrypted: RDS enforces TLS (`rds.force_ssl`), Redis uses TLS with an AUTH token. |
| SEC 11 - How do you validate application security? | Penetration testing, code review, pipeline assessment, training | One developer, so no second reviewer. Automated checks run on every change instead: Checkov, gitleaks, tflint, Go tests. The WAF's SQL injection rules were tested by hand. |
| REL 10 - How do you use fault isolation? | Multiple locations for the running workload | The ALB spans two AZs, and the app's Auto Scaling group can launch in either, but prod runs one instance; RDS, Redis and the NAT instance are single-AZ. A second instance, Multi-AZ RDS and a second Redis node would roughly double the running cost with about 80 USD of credit left. Recovery is by restore instead: final snapshots and automated backups, exercised every time dev is rebuilt after the nightly destroy (ADR-026). |
| COST 2 - How do you govern usage? | Account structure | Same Organizations constraint as SEC 1. |
| COST 7 - How do you use pricing models? | Pricing model analysis | Savings Plans and Reserved Instances need one- or three-year terms, against a four-month project paid for by credits. |

The one medium risk worth naming: **rolling deploys have no automatic rollback** (OPS 6). It
is not a setting to switch on: `scripts/deploy.sh` overwrites one fixed S3 key and creates an
unchanged launch template version, so the ASG's own rollback would relaunch instances that
download the new binary again. The manual rollback (restore the previous S3 object version,
then refresh) is now in `docs/runbooks/deployment.md`; making it automatic needs one S3 key per
version and is left for later. Blue/green deploys can already roll back instantly by shifting
the ALB weights back (ADR-017).

## Found while preparing the review

Checking each answer against the live account turned up problems no question asked about
directly. All are fixed unless noted:

- **Prod's API was down for about 40 hours, and no alarm fired** (SEV1,
  `docs/incidents/2026-09-30-db-password-rotation.md`). Secrets Manager rotates the RDS-managed
  master password every 7 days by default (ADR-009 assumed it did not), and the app read the
  password only at boot. From 2026-09-30 00:31 every request that touched the database
  returned 500, until a deploy on 2026-10-01 replaced the instance. The canary failed every
  run, but it only fed a dashboard, and its one request per 5 minutes never reached the 5xx
  alarm's threshold. Found during the REL 5 deploy. Fixed: every new connection reads the
  current password (proven with a forced rotation on 2026-10-01), every 5xx logs its cause,
  and `modules/observability` adds a `canary-failed` alarm on the canary.
- **No alarm email was ever delivered.** Every alert topic was encrypted with the AWS-managed
  `alias/aws/sns` key, which CloudWatch is not allowed to use, so from M7 until 2026-09-29 every
  alarm in dev and prod logged "Failed to execute action" instead of notifying. Every runbook in
  `docs/runbooks/` starts from an email that could never arrive. Only the account-wide `$15`
  billing alarm could deliver, on an unencrypted topic created by hand in M0, and it could never
  fire (next item). The alert topics are now
  unencrypted (`encryption-inventory.md`, G12) and a module test keeps them that way.
  **Verified on 2026-09-30:** `prod-cloudforge-ec2-cpu`, forced into ALARM with
  `aws cloudwatch set-alarm-state`, logged "Successfully executed action" on
  `prod-cloudforge-alerts`; its previous attempt, on 2026-09-16, had logged "Failed to execute
  action".
- **No cost alert could ever fire.** On the AWS Free plan credits pay every charge, so
  `EstimatedCharges` read 0.0 every day (checked back to 2026-09-20) while September cost
  113.26 USD before credits. The three CloudWatch billing alarms (account `$15`, dev and prod
  `$20`) and the console budget, which included credits, all stayed at zero, and the threat
  model and incident playbooks named them as the backstop for cost abuse. Found 2026-10-02 from
  a "$.00" in an alarm email. Fixed: the budget is now in `terraform/bootstrap/budget.tf`,
  measures cost before credits (60 USD a month, alerts at 50/80/95% of actual and 100% of
  forecast), and showed 1.55 USD of real spend right after the change. The CloudWatch billing
  alarms stay, but cannot fire while the account is on credits.
- **The prod that CI deploys was not the prod in the plan.** Multi-AZ, deletion protection,
  7-day backups and 30-day logs were only in a gitignored local `terraform.tfvars`. See "Fix in
  remediation described above; Multi-AZ stays off (REL 10) and 7-day backups are not allowed on
  the Free plan.
- **PR plans had never worked.** The first pull request (PR #1, the custom-policy demo) showed
  that the read-only plan role could not read the Redis AUTH secret it refreshes, and that the
  plan comment posted an empty output. Fixed in PR #2.
- **The daily drift check failed silently from 2026-09-19 to 09-25**, then reported a false
  "1 to add" for a canary build file on the runner's disk. Fixed in PR #2 and PR #5.
- **The nightly destroy never ran unattended.** Its job used the `dev` environment, which
  requires a reviewer, and it shared a concurrency group with `apply (dev)`: a forgotten
  approval kept dev running from 2026-09-25 to 09-27. Fixed in PR #5.
- **Real drift, found by the fixed drift check:** prod's billing-alert email subscription was
  never confirmed, so AWS deleted it after three days and prod's billing alarm notified nobody.
  Re-created and confirmed (issue #6).
- **App instances carried no project tags.** Provider `default_tags` never reach instances an
  Auto Scaling group launches; the launch template now copies them (see `policy/README.md`).
- **Not fixed: the app is never deployed to prod automatically.** `app.yml` deploys only to
  dev; prod changes only when someone runs `scripts/deploy.sh prod`. On 2026-09-29 prod was
  running a binary uploaded on 2026-09-25, older than `main`. Documented in
  `docs/runbooks/deployment.md`.
- **The canary's reports were never deleted.** It writes one to the artifacts bucket every 5
  minutes, and the bucket's lifecycle rule only expired *superseded* versions (1,631 objects in
  prod by 2026-09-30). They now expire after 31 days (`data-classification.md`, D3).
- **Not fixed:** a commit that only touches `terraform/bootstrap` still runs the whole
  `terraform` workflow and asks for dev and prod approvals it does not need.
