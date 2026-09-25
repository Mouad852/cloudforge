# Threat model

What an attacker would try against CloudForge, what stops them at each layer as built, and what was consciously not defended. Scope: the `dev` and `prod` environments, and the CI/CD path that changes them. Originally reviewed 2026-09-21; updated 2026-09-22 for ADR-025 (AWS Support permanently denied CloudFront access, so the edge was redesigned without it); updated 2026-09-25 after the redesign was applied and tested.

**The redesign is applied to `dev` and `prod` and was verified with real requests on 2026-09-24/25** (results in `docs/diagrams/traffic-flow.md` and `data-flow.md`). That testing also led to two WAF changes, both applied and re-tested on 2026-09-25: an SQL-injection rule group (T2), and an exception to the 8 KB body limit for the image upload (T8).

Threats are numbered T1 to T17. Encryption gaps are numbered G1 to G11 in `encryption-inventory.md` and are referred to by that number. The decision column here is provisional: the Well-Architected review records the final decision for each item.

## Assumptions

- CloudStore is a demo API. It has no user accounts, no personal data and no payment data. Its data has **integrity** value only.
- One operator, and **one AWS account for both environments**, on a fixed credit balance. Cost is therefore a security property: a stranger who can make the platform spend money can end the project. Cost-driven choices are recorded as accepted risks, not oversights.
- Method: for each layer, what an attacker tries, what stops them in the code as built, and what does not.

## What is being protected

| Asset | Why it matters |
|---|---|
| The AWS account and its credit balance | Everything else depends on it. Losing control means losing the project. Running up the bill has the same effect as taking it down. |
| Product data in RDS and images in S3 | Integrity and availability. There is nothing confidential in it. |
| The code that runs on the fleet | The app binary is pulled from S3 at boot (ADR-004). Whoever controls it controls every instance. |
| Secrets: RDS password, Redis AUTH token | They gate the data tier. |
| The audit trail (CloudTrail) | It is how an intrusion would be discovered and reconstructed. |
| Terraform state | It describes everything and contains two secrets (G7). |

## Who might attack

| ID | Attacker | Starting point |
|---|---|---|
| X1 | Anonymous internet client | The public ALB URL — the direct entry point (ADR-025). |
| X2 | Someone who discovers an internal name | The ALB's DNS name, or a bucket name. |
| X3 | An attacker who gets code execution on an app instance | Through a bug in the app or one of its dependencies. |
| X4 | Malicious code in CI | A hostile pull request, a compromised third-party GitHub Action, or a malicious commit on `main`. |
| X5 | Whoever holds the operator's access key | A compromised laptop. |

Out of scope: AWS itself and its staff, and a region-wide outage (that is M11, disaster recovery).

## Trust boundaries and the controls on each

| Boundary | Controls as built | Defined in |
|---|---|---|
| Internet to the ALB (the public edge, ADR-025) | HTTP only, no HTTPS listener (G11). `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: same-origin` set by app middleware (moved from CloudFront's response-headers policy — no HSTS, dropped rather than sent incorrectly over HTTP). `drop_invalid_header_fields` is on. AWS Shield Standard applies automatically to the ALB. | `modules/edge`, `app/middleware.go` |
| WAF on the ALB | `REGIONAL`-scope web ACL, associated directly with the ALB (`aws_wafv2_web_acl_association`), default action allow. Rules in order: `AWSManagedRulesCommonRuleSet` (with its 8 KB `SizeRestrictions_BODY` rule set to count), `AWSManagedRulesKnownBadInputsRuleSet`, `AWSManagedRulesAmazonIpReputationList`, `RateLimitPerIP` (block above `waf_rate_limit`, default 2000 requests per 5 minutes per IP), `AWSManagedRulesSQLiRuleSet` (T2), then `OversizedBodyExceptImageUpload`, which blocks bodies over 8 KB on every path except `/api/products/{id}/image` (T8). The last two were added on 2026-09-25. Metrics and sampled requests on; no request logging. | `modules/edge` |
| ALB to app instances | ALB security group ingress: `0.0.0.0/0` on port 80 — deliberate, this is the public edge now (ADR-025). Egress: only the app port, only to the VPC CIDR. App security group ingress: only from the ALB security group. Instances sit in private subnets with no public IP. | `modules/edge`, `modules/compute` |
| App to data tier | RDS security group ingress: 5432 only from the app security group. Redis security group ingress: 6379 only from the app security group. Data subnets are private and RDS is not publicly accessible. RDS forces TLS, Redis needs TLS plus an AUTH token. Passwords come from Secrets Manager. | `modules/database`, `modules/cache` |
| App to AWS APIs | The instance role (below). IMDSv2 required. The app security group's only internet egress is port 443. S3 traffic uses the gateway endpoint. | `modules/compute`, `modules/network` |
| GitHub Actions to AWS | OIDC, no stored keys. Two roles split by trigger, with the audience and the immutable repository subject checked in each trust policy. | `modules/cicd-oidc` |
| Operator to instances | SSM Session Manager only. No SSH, no key pairs, no bastion (ADR-005). | `modules/compute` |

The security-group chain, in order: ALB security group (open to the internet by design, ADR-025), then app security group, then RDS and Redis security groups. Only the first hop is intentionally open; every hop after it accepts only the hop before it.

## IAM principals

| Principal | Assumed or used by | Scope | Worst case if abused |
|---|---|---|---|
| `<env>-cloudforge-app` (instance role) | The app fleet | Read the artifacts bucket, read and write the images bucket, read the RDS and Redis secrets, put metrics into `CloudForge/EC2`, write its own log group, plus SSM core | Full read and write on product data and images, and the ability to read both data-tier secrets. That is what the app needs. |
| `<env>-nat-instance` | The NAT instance | SSM core only | Session access to one instance. |
| `<env>-vpc-flow-logs` | VPC flow logs service | Write to one log group | Negligible. |
| `<env>-cloudforge-canary` | The Synthetics canary | Write objects under `canary/<env>/` in the artifacts bucket, put metrics in the `CloudWatchSynthetics` namespace, write `cwsyn-*` log groups | Can write under its own prefix only. It cannot touch the app binary. |
| `cloudforge-github-actions-terraform-plan` | Any `pull_request` run, and scheduled or manual runs on `main` | `ReadOnlyAccess` plus `sns:Publish` on the two alerts topics | Read all configuration, including Terraform state (G7). |
| `cloudforge-github-actions-terraform-apply` | Runs on `main`, and jobs with `environment: dev` or `prod` | `PowerUserAccess` plus IAM actions on roles and instance profiles named `dev-*`, `prod-*`, `test-*` | Effectively the whole account, see T12. |
| `cloudforge-admin` (IAM user, long-lived key) | The operator | Administrative | The whole account (ADR-021). |

## Threat register

Decision values: **Accepted** (a conscious trade-off), **Fix candidate** (worth changing, to be decided in the review), **Verify** (depends on a setting not yet checked).

| ID | Threat | What stops it | What does not | Decision |
|---|---|---|---|---|
| T1 | X1 creates or deletes products, or overwrites any product's image. | WAF managed rules and the per-IP rate limit. | **The API has no authentication.** `POST /api/products`, `DELETE /api/products/{id}` and `POST /api/products/{id}/image` are open, and the image key is predictable (`products/<id>`). | Accepted. It is a demo with no user accounts. Recorded in the review. |
| T2 | X1 sends known-bad web payloads (SQL injection strings, scanner traffic, known bad IPs). | WAF Common, KnownBadInputs and IP Reputation rule groups block scanners and known-bad inputs before the ALB forwards the request. SQL injection is matched by `AWSManagedRulesSQLiRuleSet` (added 2026-09-25). Behind the WAF, the app is not injectable: every query uses placeholders (`$1`, `$2`) and the list endpoint ignores query parameters. | **Until 2026-09-25 the WAF did not block SQL injection at all.** `CommonRuleSet` has no SQL-injection rules. A request with `' OR '1'='1` in the query string passed all four rule groups and reached the app with a `200` (sent from CloudShell and confirmed in the WAF's sampled requests). Managed rules do not stop logic abuse (T1). No bot control. | Fixed and verified 2026-09-25: the same request now gets `403` on both environments, blocked by `SQLi_QUERYARGUMENTS`. |
| T3 | ~~X2 bypasses CloudFront by calling the ALB directly, or through another customer's CloudFront distribution.~~ | n/a | n/a | **No longer applicable (ADR-025).** There is no CloudFront to bypass — the ALB is the direct, intended public entry point now, the same address every client uses. |
| T4 | X1 floods the API, or drives up cost ("denial of wallet"). | Shield Standard, the per-IP WAF rate limit, and the billing alarm and budget as a backstop. | A distributed flood under the per-IP limit still reaches the origin, because API responses are never cached. The fleet scales up on CPU, which costs money. No Shield Advanced, no geo-blocking, no bot control. | Accepted. The budget alarm is the real backstop. |
| T5 | X3 uses code execution on an instance to escalate or exfiltrate. | Private subnet, no public IP, no SSH, IMDSv2 required, an instance role limited to specific buckets, secrets and log group. | **The app runs as root** (the systemd unit has no `User=` and no hardening options). Egress to any host on port 443 is open, so exfiltration or command-and-control is possible. | Fix candidate for root. Egress accepted. |
| T6 | X3 moves from an instance to the database or cache. | The security-group chain and TLS. Nothing else in the VPC can reach 5432 or 6379. | A compromised app instance has the credentials by design, so it has full data access. | Accepted |
| T7 | X1 or X2 reaches RDS, Redis or S3 directly from the internet. | Private subnets, no public access on RDS, security groups, S3 public access blocks on all four buckets, TLS-only bucket policies on all four (G6). Images are readable only through the app's own IAM role (ADR-025) — the bucket has no public grant of any kind, not even a CDN-scoped one. | Nothing known. | Accepted (working as intended) |
| T8 | X1 uploads hostile content through the image endpoint. | 5 MiB body limit in the app, `nosniff` header. The WAF's 8 KB body limit deliberately does not apply to this one path, since it blocked every real image (fixed 2026-09-25); every other path keeps it. | The client's `Content-Type` is stored unchanged, and images are served by the same app and the same origin as the API (`GET /api/products/{id}/image`, ADR-025) — there is no longer even a separate CDN behavior boundary between them. An uploaded `text/html` object would run as that origin. There are no cookies or sessions to steal, so the impact is low. | Fix candidate (allow only `image/*` types) |
| T9 | Someone replaces the app binary in the artifacts bucket. | The bucket is private, versioned and TLS-only. Only the admin user and the apply role can write to it. | The instance downloads the binary and runs it with no checksum or signature check. One bad object at that key runs on every instance that boots. | Fix candidate (record a SHA-256 at deploy, verify at boot) |
| T10 | X4 uses a hostile pull request to reach AWS. | Fork pull requests do not receive an OIDC token (GitHub's documented behaviour, not tested here). The plan role is read-only. | A pull request from a branch in this repository runs its own workflow code and can assume the plan role, which can read all configuration and the state file (G7). | Accepted for a single operator. Verify the fork-approval setting. |
| T11 | X4 through a compromised or retagged third-party Action. | `.terraform.lock.hcl` pins provider hashes. The lint job, which runs the least-trusted tooling, has no AWS credentials. | Actions are referenced by major tag (`@v4`, `@v3`, `@v12`), not by commit SHA. Several steps use `latest` (`tflint_version`, `govulncheck@latest`). Credentials configured by an earlier step are visible to later third-party steps in the same job. | Fix candidate (pin by SHA) |
| T12 | X4 through a malicious commit on `main`, or a compromised apply job, escalates to full administrator. | OIDC subject conditions, branch protection on `main`, and the GitHub environment approval for `dev` (Verify for `prod`). | **The IAM name-prefix scope is a guardrail, not a boundary.** The apply role can create a role named `dev-x`, attach any managed policy to it, pass it to an EC2 instance, or let the apply role assume it. Read from the policy, not tested. There is no permissions boundary. | Fix candidate (permissions boundary on roles the apply role creates). The rest is accepted, as `github-oidc-trust-policy.md` already states. |
| T13 | X5 uses a stolen operator key. | Key never committed (gitleaks pre-commit hook), periodic rotation, key deleted at teardown (ADR-021). | A stolen key is full administrator. ADR-021 says gitleaks also runs in CI, but no workflow contains a gitleaks step. MFA on the admin user is not yet verified. | Accepted (ADR-021). Fix candidate for the missing CI secret scan. Verify MFA. |
| T14 | An attacker with the apply role or the admin key covers their tracks. | CloudTrail records management events in all regions. | `PowerUserAccess` can stop the trail or delete its log objects. Log file validation is off, there is no CloudWatch Logs delivery so nothing alerts on trail changes, and data events are not recorded (G5). | Fix candidate (enable log file validation) |
| T15 | An intrusion goes unnoticed. | CloudWatch alarms on availability and load, VPC flow logs, WAF sampled requests, and GuardDuty during its 30-day trial. | After the trial there is no threat detection, and nobody analyses the flow logs. | Accepted, on cost |
| T16 | A dev mistake or compromise reaches prod. | Separate state files (ADR-002), separate directories, an approval gate on the prod apply job. | One AWS account, one apply role, and one state bucket serve both environments. | Accepted (ADR-012, cost) |
| T17 | X1 learns about the platform from public endpoints. | Nothing sensitive is returned. | `GET /whoami` returns the instance ID and availability zone. `GET /readyz` reveals whether the database and cache are up. Both are reachable through the ALB directly. | Accepted (low) |

## What was consciously not defended against

- **Authentication and authorization for API users.** There are no users (T1).
- **Distributed floods and cost abuse beyond the per-IP limit.** The budget alarm limits the damage, it does not stop it (T4).
- **Plaintext everywhere.** There is no TLS at all between a client and the ALB (G11), and none between the ALB and instances (G2) — a real regression from the CloudFront-fronted design, accepted deliberately (ADR-025).
- **A malicious commit that reaches `main`.** IAM scoping limits accidents, not a determined attacker (T12).
- **A compromised operator laptop** (T13).
- **Data exfiltration from a compromised instance.** There is no egress filtering (T5).
- **Threat detection after the GuardDuty trial ends** (T15).
- **Customer-managed encryption keys** (G4) and **separation into multiple AWS accounts** (T16).

## Open verifications

Settings that change the answers above and have not been checked yet:

- [x] The CloudShell test request from T2 gets a `403`, and the sampled requests name `AWSManagedRulesSQLiRuleSet` (T2). Verified 2026-09-25. Send it from CloudShell, not the operator's own network (see `docs/diagrams/traffic-flow.md`).
- [ ] Branch protection on `main`: pull request required, the `lint` check required, force pushes blocked (T12).
- [ ] GitHub environment `prod` has required reviewers, as `dev` does (T12, T16).
- [ ] The Actions setting that requires approval before workflows run from fork pull requests (T10).
- [ ] GitHub secret scanning and push protection are on, since no workflow runs gitleaks (T13).
- [ ] MFA is enabled on the `cloudforge-admin` user, the root user has MFA and no access keys, and the admin access key's age (T13).
