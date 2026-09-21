# Encryption inventory

Every place CloudForge stores data, and every network hop that data crosses, with the key type behind each. Reviewed against the Terraform and app code in this repository at commit `2e75a94` (2026-09-20). Resources marked *console* were created by hand in M0 and are not in Terraform.

Gaps found while building this table are numbered G1 to G8 at the bottom. The threat model and the Well-Architected review refer to them by number and record the final decision for each.

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
| Images bucket `cloudforge-images-<env>-*` | `modules/storage/main.tf`, policy in `modules/edge/main.tf` | Yes | SSE-S3 | Readable only through CloudFront (OAC), TLS-only policy. |
| ALB access-log bucket `cloudforge-alb-logs-<env>-*` | `terraform/modules/edge/main.tf` | Yes | SSE-S3 | ALB access logs can only be delivered to an SSE-S3 bucket, so a KMS key is not an option here. Its policy has no TLS-only deny, see G6. |
| RDS Postgres storage, automated backups and snapshots (including the final snapshot taken on destroy) | `terraform/modules/database/main.tf` | Yes (`storage_encrypted = true`) | AWS-managed `aws/rds` (no `kms_key_id` set) | Backups and snapshots inherit the instance's key. |
| RDS Performance Insights data | `modules/database/main.tf` | Yes | AWS-managed `aws/rds` (default) | Checkov `CKV_AWS_354` is skipped for this, see G4. |
| RDS Postgres log export (CloudWatch log group) | `modules/database/main.tf` | Yes | Service-managed (CloudWatch Logs default) | `enabled_cloudwatch_logs_exports = ["postgresql"]`. |
| ElastiCache Redis (node disk during sync and swap, and any backups) | `terraform/modules/cache/main.tf` | Yes (`at_rest_encryption_enabled = true`) | Service-managed key, `StorageEncryptionType = sse-elasticache` per the AWS documentation | No customer key is set. No snapshot retention is configured, so no backups exist. The comment in `.pre-commit-config.yaml` calls this key "AWS-managed"; it is more precisely service-managed and not visible in KMS. |
| Secrets Manager: RDS master password `rds!db-*` | created by RDS (ADR-009) | Yes | AWS-managed `aws/secretsmanager` | Terraform never sees the password value. |
| Secrets Manager: Redis AUTH token `cloudforge/<env>/redis-auth` | `modules/cache/main.tf` | Yes | AWS-managed `aws/secretsmanager` (no `kms_key_id` set) | The same token is also in Terraform state, see G7. |
| EBS root volumes, app fleet | `terraform/modules/compute/main.tf` (launch template) | Yes (`encrypted = true`) | AWS-managed `aws/ebs`, unless the account default was changed (not yet checked) | Instances are stateless. The volume holds the OS and the app binary. |
| EBS root volume, NAT instance | `terraform/modules/network/main.tf` | Yes (`encrypted = true`) | Same as above | |
| CloudWatch log groups: app `/cloudforge/<env>/app`, VPC flow logs `/aws/vpc/<env>-cloudforge`, canary `/aws/lambda/cwsyn-*` | `modules/compute`, `modules/network`, created by Synthetics | Yes | Service-managed (CloudWatch Logs default) | No `kms_key_id` on any group. Checkov `CKV_AWS_158` is skipped, see G4. |
| SNS topics `<env>-cloudforge-alerts` and the billing topic | `terraform/modules/observability/main.tf` | Yes | AWS-managed `alias/aws/sns` | |
| SNS topic `cloudforge-billing-alerts` (*console*, M0) | not in Terraform | Not checked yet | Unknown | To be confirmed, see "How this was checked". |
| CloudTrail `management-events` and its log bucket (*console*, M0) | not in Terraform | Yes, S3 default | SSE-S3 (SSE-KMS shows "Not enabled") | Per the 2026-09-05 screenshot in `docs/screenshots/00-foundations/`: log file validation disabled, no CloudWatch Logs. See G5. |

**Customer-managed KMS keys in the project: 0.**

## Secrets and where each one lives

| Secret | Created by | Stored in | Also present in |
|---|---|---|---|
| RDS master password | RDS (`manage_master_user_password`, ADR-009) | Secrets Manager only | Nowhere else. Not in Terraform state. |
| Redis AUTH token | `random_password.redis_auth` | Secrets Manager | Terraform state (plaintext) |
| `X-Origin-Verify` header value (ADR-014) | `random_password.origin_secret` | CloudFront origin config and the ALB listener rule | Terraform state (plaintext). Also crosses the network in clear text, see G1. |

## Data in transit

| Hop | Protocol | Encrypted | Server identity verified | Notes |
|---|---|---|---|---|
| Viewer to CloudFront | HTTPS (`redirect-to-https` on all three behaviors) | Yes | Yes | The free `*.cloudfront.net` certificate forces a minimum protocol of TLSv1 (ADR-011, G8). |
| CloudFront to images bucket | HTTPS, signed with OAC (SigV4) | Yes | Yes | The bucket policy also denies any non-TLS request. |
| **CloudFront to ALB** | **HTTP, port 80** (`origin_protocol_policy = "http-only"`) | **No** | n/a | Carries the `X-Origin-Verify` secret. See G1. |
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
| G1 | CloudFront reaches the ALB over plain HTTP, so the `X-Origin-Verify` secret is readable by anyone who can observe that hop. | Accepted | An HTTPS origin needs a certificate matching the ALB's name, which needs a domain. ADR-011 rejected the domain on cost. The security group (CloudFront prefix list) and the header still block casual direct access. |
| G2 | ALB to instances is plain HTTP. | Accepted | The hop stays inside private subnets and the instance SG accepts only the ALB SG. TLS on every instance means distributing and renewing certificates. |
| G3 | The Postgres connection is encrypted but not authenticated (`sslmode=require`). | Candidate fix | `verify-full` would fail the same way as ADR-022, because the app dials the `db.cloudforge.internal` CNAME and the certificate is issued for RDS's own hostname. `verify-ca` avoids the hostname check but needs the RDS CA bundle on the instances. Decided in the Well-Architected review. |
| G4 | No customer-managed KMS keys anywhere. | Accepted | Cost on a fixed credit balance. Same call as the Checkov skips for `CKV_AWS_145`, `CKV_AWS_149`, `CKV_AWS_158`, `CKV_AWS_191` and `CKV_AWS_354`. The consequence is no key-level kill switch and no per-use KMS audit for S3 objects. |
| G5 | CloudTrail: log file validation disabled, no SSE-KMS, no CloudWatch Logs (as of the 2026-09-05 screenshot). | Candidate fix | Log file validation is free and lets us prove the logs were not altered. Confirm the current state first. |
| G6 | The ALB access-log bucket policy has no TLS-only deny, unlike the state, artifacts and images buckets. | Candidate fix | A small Terraform change in `modules/edge`. It needs a check that ALB log delivery still works with the deny in place. |
| G7 | Terraform state holds the Redis AUTH token and the origin header secret in plaintext. | Accepted | The bucket is private, versioned, TLS-only and SSE-S3. The CI plan role can read state by design, because `terraform plan` needs it. |
| G8 | Viewer TLS floor is TLSv1 on the default CloudFront certificate. | Accepted | This is the price of ADR-011. Checkov `CKV_AWS_174` and `CKV2_AWS_42` are skipped for it. |

## What holds no data of its own

- **CloudFront and WAF:** no access logs and no WAF logging are configured, only sampled requests and metrics in the console.
- **Route 53 private zone, security groups, IAM, VPC endpoints:** configuration only.
- **GitHub secrets and variables:** outside AWS. The only secret is the Infracost API key, which is not an AWS credential.

## How this was checked

- **Code:** every row above was read from the Terraform and app source listed in its "Defined in" column.
- **ElastiCache key type:** from the AWS documentation page "At-Rest Encryption in ElastiCache".
- **CloudTrail row:** from the 2026-09-05 console screenshot. Not re-checked live at the time of writing.
- **Not yet checked live:** the console SNS topic's encryption, the account's default EBS key, and the current CloudTrail settings. Live results are recorded below once run.
