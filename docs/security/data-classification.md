# Data classification

What CloudForge stores, how sensitive each kind of data is, and the controls and retention that
follow from that. Written in M10 for the Well-Architected review (SEC 7). Encryption details for
every store are in `encryption-inventory.md`; this document decides *how much protection each
store needs* and checks it gets that.

## Levels

| Level | Meaning | If it leaked | Required controls |
|---|---|---|---|
| **Public** | Meant to be published: the catalogue a shop shows its customers. | Nothing; the risk is someone *changing* it. | Encrypted at rest; private storage, written only through the app; versioned or backed up. |
| **Internal** | Operational data about the system itself. | Helps an attacker map the system. | Encrypted at rest; private; readable only through IAM; retention set. |
| **Confidential** | Personal data: IP addresses and user agents of visitors, the operator's identity. Under the GDPR an IP address is personal data. | A privacy breach. | Everything above, plus: kept in the EU, retention limited to what debugging needs, never copied out of AWS. |
| **Restricted** | Credentials that grant access to other data. | Direct access to the database or cache. | Secrets Manager or the state bucket only; never in code, logs or tickets (gitleaks in pre-commit and CI); readable by as few roles as possible. |

## Inventory

| Data | Where | Level | Retention |
|---|---|---|---|
| Products: `id`, `name`, `price_cents`, `image_key`, `created_at` | RDS `products` table | Public | Until deleted; automated backups 1 day (the Free plan maximum), a final snapshot on every destroy |
| Product images | S3 images bucket | Public | Until deleted; versioned |
| Cached products | ElastiCache Redis | Public (a copy of the table) | 60-second TTL; no Redis backups |
| App binary, canary output | S3 artifacts bucket | Internal | Superseded versions expire after 90 days |
| App request logs: request ID, method, path, status, duration | CloudWatch Logs `/cloudforge/<env>/app` | Internal | 30 days in prod, 14 in dev |
| Postgres logs | CloudWatch Logs `/aws/rds/instance/<env>-cloudforge-db/postgresql` | Internal | **None set: kept forever** (gap D3) |
| Performance Insights | RDS | Internal | 7 days (the free tier) |
| Synthetics canary run logs | CloudWatch Logs `/aws/lambda/cwsyn-<env>-api-avail-*` | Internal | **None set: kept forever, and outlive dev's nightly destroy** (gap D3) |
| Alarm notifications: alarm name, state, metric value | SNS topics (unencrypted on purpose, see below), then email | Internal | Deleted by SNS once delivered; then in the recipient's mailbox |
| ALB access logs: client IP, user agent, request line | S3 ALB-logs bucket | **Confidential** | Expire after 90 days |
| VPC flow logs: source and destination IPs, ports | CloudWatch Logs `/aws/vpc/<env>-cloudforge` | **Confidential** | 30 days in prod, 14 in dev |
| WAF sampled requests: client IP, headers | WAF console | **Confidential** | Kept by AWS for 3 hours; no WAF logging is configured |
| CloudTrail: API calls, caller identity, source IP | CloudTrail bucket (*console*, M0) | **Confidential** | **None set: kept forever** (gap D2) |
| RDS master password | Secrets Manager `rds!db-*` | **Restricted** | Rotated by AWS (ADR-009) |
| Redis AUTH token | Secrets Manager `cloudforge/<env>/redis-auth`, and Terraform state | **Restricted** | Not rotated (Checkov `CKV2_AWS_57` skip) |
| Terraform state | S3 state bucket | **Restricted** (holds the Redis token) | Superseded versions expire after 90 days |

**No customer accounts, orders, payment data or personal data are stored by the application
itself.** The app's own logs were written that way on purpose: `withRequestLogging` in
`app/main.go` records the path but not the query string, body, headers or client IP. All personal
data in the system is visitor metadata collected by AWS services in front of the app.

## Does each store get the controls its level requires?

- **Public and Internal:** encrypted at rest, private and reachable only through IAM, with public
  access blocked on every bucket. Retention is set on everything Terraform creates, but **not on
  the two log groups AWS services create by themselves** (gap D3). One accepted exception to
  encryption at rest: the alert SNS topics, because CloudWatch alarms cannot publish to a topic
  encrypted with the AWS-managed key (`encryption-inventory.md`, G12).
- **Confidential:** yes for the ALB logs, flow logs and WAF, all kept in eu-west-3 with limited
  retention. **Not for CloudTrail** (gap D2).
- **Restricted:** yes for Secrets Manager. The Redis token also sitting in Terraform state is
  accepted in `encryption-inventory.md` (G7): the bucket is private, versioned, TLS-only and
  readable only by the admin user and the two CI roles.

## Gaps

| # | Gap | Decision |
|---|---|---|
| D1 | Classification is manual. Nothing detects personal data appearing somewhere new (for example, a future change that logs client IPs in the app). | Accepted. Amazon Macie does this automatically, but it is priced per GB scanned plus per bucket, on a fixed credit balance. The app's request logging is the only place the application itself could start leaking personal data, and it is small enough to review by eye. |
| D2 | The CloudTrail bucket, created by hand in M0, has no lifecycle rule, so personal data (operator identity, source IPs) is kept indefinitely. | Candidate fix, with the other CloudTrail gaps in `encryption-inventory.md` (G5). |
| D3 | Log groups that AWS services create by themselves have no retention: RDS's Postgres log export and the Synthetics canary's Lambda logs. They are not in Terraform, so dev's nightly destroy leaves them behind: on 2026-09-29 there were five orphaned dev canary log groups, one per rebuild. | Candidate fix. The RDS group has a predictable name, so Terraform can create it first with a retention (and delete it on destroy). The canary's group name contains a generated ID, so it needs a different approach. |
