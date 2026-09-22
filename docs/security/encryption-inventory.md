# Encryption inventory

Every place CloudForge stores data, and every network hop that data crosses, with the key type behind each. Originally reviewed at commit `2e75a94` (2026-09-20); updated 2026-09-22 for ADR-025 (AWS Support permanently denied CloudFront access, so the edge was redesigned without it — see that ADR for the full context). Resources marked *console* were created by hand in M0 and are not in Terraform.

**The redesign in this update is not yet applied to `dev` or `prod`.** Rows describing the ALB's direct-edge behavior describe the code as written, not yet a live, verified fact — unlike the rest of this table, which was checked against real infrastructure.

Gaps found while building this table are numbered G1 to G11 at the bottom. The threat model and the Well-Architected review refer to them by number and record the final decision for each. G1 and G8 are marked resolved below rather than renumbered, so the numbering stays stable for anything that already cites them.

## Key types used in this project

| Term | What it means here | Where it appears |
|---|---|---|
| SSE-S3 | S3 encrypts every object with keys it manages itself. No key shows up in the account's KMS, there is no key policy, and there is no per-use audit trail. | Every S3 bucket |
| AWS-managed KMS key (`aws/<service>`) | AWS creates the key in this account the first time the service needs it. It is visible in KMS, its policy cannot be edited, and AWS rotates it. | RDS, Secrets Manager, EBS, SNS |
| Service-managed key | The key lives entirely inside the service and is not visible in the account. | ElastiCache, CloudWatch Logs |
| Customer-managed KMS key | A key created and owned by us, with our own policy and rotation setting. | **None, on purpose.** About $1 a month per key on a fixed credit balance. See G4. |

## Data at rest

| Data store | Defined in | Encrypted at rest | Key | Notes |
|---|---|---|---|---|
| Terraform state bucket `cloudforge-tfstate-*` | `terraform/bootstrap/main.tf` | Yes | SSE-S3 (`AES256`) | Versioned, public access blocked, TLS-only bucket policy. Contains two secrets in plaintext, see G7. |
| Artifacts bucket `cloudforge-artifacts-<env>-*` | `terraform/modules/storage/main.tf` | Yes | SSE-S3 | Holds the app binary and the Synthetics canary output (`canary/<env>/`). Versioned, TLS-only policy. |
| Images bucket `cloudforge-images-<env>-*` | `modules/storage/main.tf` | Yes | SSE-S3 | Readable and writable only through the app's own IAM role (ADR-025 — no CloudFront/OAC any more), TLS-only policy. |
| ALB access-log bucket `cloudforge-alb-logs-<env>-*` | `terraform/modules/edge/main.tf` | Yes | SSE-S3 | ALB access logs can only be delivered to an SSE-S3 bucket, so a KMS key is not an option here. Its policy has no TLS-only deny, see G6. |
| RDS Postgres storage, automated backups and snapshots (including the final snapshot taken on destroy) | `terraform/modules/database/main.tf` | Yes (`storage_encrypted = true`) | AWS-managed `aws/rds` (no `kms_key_id` set) | Backups and snapshots inherit the instance's key. |
| RDS Performance Insights data | `modules/database/main.tf` | Yes | AWS-managed `aws/rds` (default) | Checkov `CKV_AWS_354` is skipped for this, see G4. |
| RDS Postgres log export (CloudWatch log group) | `modules/database/main.tf` | Yes | Service-managed (CloudWatch Logs default) | `enabled_cloudwatch_logs_exports = ["postgresql"]`. |
| ElastiCache Redis (node disk during sync and swap, and any backups) | `terraform/modules/cache/main.tf` | Yes (`at_rest_encryption_enabled = true`) | Service-managed key, `StorageEncryptionType = sse-elasticache` per the AWS documentation | No customer key is set. No snapshot retention is configured, so no backups exist. The comment in `.pre-commit-config.yaml` calls this key "AWS-managed"; it is more precisely service-managed and not visible in KMS. |
| Secrets Manager: RDS master password `rds!db-*` | created by RDS (ADR-009) | Yes | AWS-managed `aws/secretsmanager` | Terraform never sees the password value. |
| Secrets Manager: Redis AUTH token `cloudforge/<env>/redis-auth` | `modules/cache/main.tf` | Yes | AWS-managed `aws/secretsmanager` (no `kms_key_id` set) | The same token is also in Terraform state, see G7. |
| EBS root volumes, app fleet | `terraform/modules/compute/main.tf` (launch template) | Yes (`encrypted = true`) | AWS-managed `aws/ebs` (the account's default EBS key is `alias/aws/ebs`, confirmed live) | Instances are stateless. The volume holds the OS and the app binary. The account-wide "encryption by default" setting is off, see G9. |
| EBS root volume, NAT instance | `terraform/modules/network/main.tf` | Yes (`encrypted = true`) | Same as above | |
| CloudWatch log groups: app `/cloudforge/<env>/app`, VPC flow logs `/aws/vpc/<env>-cloudforge`, canary `/aws/lambda/cwsyn-*` | `modules/compute`, `modules/network`, created by Synthetics | Yes | Service-managed (CloudWatch Logs default) | No `kms_key_id` on any group. Checkov `CKV_AWS_158` is skipped, see G4. |
| SNS topics `<env>-cloudforge-alerts` (eu-west-3) and `<env>-cloudforge-billing-alerts` (us-east-1, because billing metrics only publish there) | `terraform/modules/observability/main.tf` | Yes | AWS-managed `alias/aws/sns` | Confirmed live on 2026-09-21. |
| SNS topic `cloudforge-billing-alerts` (*console*, M0, us-east-1) | not in Terraform | No | None | Confirmed live on 2026-09-21: no KMS key is set, so messages are not encrypted at rest. Created by hand in M0 without encryption. See G10. |
| CloudTrail `management-events` and its log bucket (*console*, M0) | not in Terraform | Yes, S3 default | SSE-S3 (SSE-KMS shows "Not enabled") | Confirmed live on 2026-09-21 (and in the 2026-09-05 screenshot in `docs/screenshots/00-foundations/`): log file validation disabled, no KMS key, no CloudWatch Logs. See G5. |

**Customer-managed KMS keys in the project: 0.**

## Secrets and where each one lives

| Secret | Created by | Stored in | Also present in |
|---|---|---|---|
| RDS master password | RDS (`manage_master_user_password`, ADR-009) | Secrets Manager only | Nowhere else. Not in Terraform state. |
| Redis AUTH token | `random_password.redis_auth` | Secrets Manager | Terraform state (plaintext) |

The `X-Origin-Verify` header secret (ADR-014) no longer exists — it gated the CloudFront-to-ALB hop, which is gone (ADR-025).

## Data in transit

| Hop | Protocol | Encrypted | Server identity verified | Notes |
|---|---|---|---|---|
| **Viewer to ALB** | **HTTP, port 80** — the ALB has no HTTPS listener | **No** | n/a | ADR-025: with no CloudFront to supply a free certificate, and no domain bought to replace it, the ALB is the public edge and stays HTTP-only. See G11. |
| **ALB to app instances** | **HTTP, app port (8080)** | **No** | n/a | Stays inside the private VPC. Instance SG accepts only the ALB SG. See G2. |
| App to RDS | TLS, `sslmode=require` (`app/config.go`) | Yes, and `rds.force_ssl = 1` makes RDS refuse plaintext | **No** by PostgreSQL's definition of `require`, which encrypts without checking the certificate | See G3. |
| App to Redis | TLS (`transit_encryption_enabled`), minimum TLS 1.2, plus AUTH token | Yes | Yes, against ElastiCache's own hostname (ADR-022) | `app/cache.go` sets `MinVersion: tls.VersionTLS12` and `ServerName`. |
| App to S3, Secrets Manager, CloudWatch, SSM | HTTPS through the AWS SDK and agents | Yes | Yes | The app SG's only internet egress is port 443, so it cannot make a plaintext outbound call. S3 goes through the gateway endpoint, the rest through NAT. |
| Operator to an instance | SSM Session Manager (TLS) | Yes | Yes | No SSH, no key pairs, no bastion (ADR-005). |
| GitHub Actions to AWS | OIDC token exchange, then API calls over HTTPS | Yes | Yes | Terraform reads and writes state over HTTPS. The state bucket denies non-TLS. |
| SNS to email subscribers | Depends on the recipient's mail provider | Not under our control | n/a | Alerts carry alarm names and metric values, not application data. |

## Gaps

| # | Gap | Status | Reasoning |
|---|---|---|---|
| G1 | ~~CloudFront reaches the ALB over plain HTTP, so the `X-Origin-Verify` secret is readable by anyone who can observe that hop.~~ | **Resolved by ADR-025 — no longer applicable** | There is no CloudFront-to-ALB hop any more; the secret it protected no longer exists. See G11 for the gap that replaces this one. |
| G2 | ALB to instances is plain HTTP. | Accepted | The hop stays inside private subnets and the instance SG accepts only the ALB SG. TLS on every instance means distributing and renewing certificates. |
| G3 | The Postgres connection is encrypted but not authenticated (`sslmode=require`). | Candidate fix | `verify-full` would fail the same way as ADR-022, because the app dials the `db.cloudforge.internal` CNAME and the certificate is issued for RDS's own hostname. `verify-ca` avoids the hostname check but needs the RDS CA bundle on the instances. Decided in the Well-Architected review. |
| G4 | No customer-managed KMS keys anywhere. | Accepted | Cost on a fixed credit balance. Same call as the Checkov skips for `CKV_AWS_145`, `CKV_AWS_149`, `CKV_AWS_158`, `CKV_AWS_191` and `CKV_AWS_354`. The consequence is no key-level kill switch and no per-use KMS audit for S3 objects. |
| G5 | CloudTrail: log file validation disabled, no SSE-KMS, no CloudWatch Logs (confirmed live on 2026-09-21). | Candidate fix | Log file validation is free and lets us prove the logs were not altered. |
| G6 | The ALB access-log bucket policy has no TLS-only deny, unlike the state, artifacts and images buckets. | Candidate fix | A small Terraform change in `modules/edge`. It needs a check that ALB log delivery still works with the deny in place. |
| G7 | Terraform state holds the Redis AUTH token in plaintext. | Accepted | The bucket is private, versioned, TLS-only and SSE-S3. The CI plan role can read state by design, because `terraform plan` needs it. (Previously also listed the origin-header secret, ADR-014 — that secret no longer exists, ADR-025.) |
| G8 | ~~Viewer TLS floor is TLSv1 on the default CloudFront certificate.~~ | **Resolved by ADR-025 — no longer applicable** | There is no CloudFront certificate, or any TLS at all, between the viewer and the ALB. See G11. |
| G9 | EBS encryption by default is off for the account in eu-west-3 (`EbsEncryptionByDefault: false`). Only volumes that set `encrypted = true` are encrypted, which every volume in Terraform does. | Candidate fix | A volume created by hand, or by a future module that forgets the flag, would be unencrypted. Turning the setting on is free and affects only new volumes. It is an account-level, per-region setting, so it lives outside the environment stacks. Decided in the Well-Architected review. |
| G10 | The M0 console-created SNS topic `cloudforge-billing-alerts` (us-east-1) has no server-side encryption. | Candidate fix | Free to fix: turn on SNS encryption with `alias/aws/sns`, the key the Terraform-managed topics already use. The content is budget alarm text, not application data, so the risk is low. Before deciding between encrypting it and deleting it, check which alarms and budgets still point at it. Decided in the Well-Architected review. |
| G11 | The ALB has no HTTPS listener at all — every hop from the viewer to the ALB is plaintext HTTP, no encryption and no server identity check. | Accepted | ADR-025: real HTTPS on an ALB needs a certificate bound to a domain name, and buying one reopens the recurring cost ADR-011 already declined once. A real regression from the CloudFront-fronted design, accepted deliberately rather than overlooked. |

## What holds no data of its own

- **WAF:** no request logging configured, only sampled requests and metrics in the console. (Previously also listed CloudFront — gone, ADR-025.)
- **Route 53 private zone, security groups, IAM, VPC endpoints:** configuration only.
- **GitHub secrets and variables:** outside AWS. The only secret is the Infracost API key, which is not an AWS credential.

## How this was checked

- **Code:** every row above was read from the Terraform and app source in its "Defined in" column.
- **ElastiCache key type:** the AWS documentation page "At-Rest Encryption in ElastiCache", then confirmed live: both replication groups report `StorageEncryptionType = sse-elasticache`.
- **Live checks on 2026-09-21 (read-only):** CloudTrail trail settings, the SNS topic keys in eu-west-3 and us-east-1, the RDS key manager (`AWS`, checked on the first instance returned), ElastiCache encryption status, and the account's EBS defaults (`EbsEncryptionByDefault = false`, default key `alias/aws/ebs`).
- **Not checked live:** the S3 buckets' encryption and policies (read from Terraform only), and any other RDS instance's key (same module, same code).
