# High-Level Architecture

Target design (`PLAN.md` §5). This is the **pre-implementation** version — expect details here to firm up, and possibly change, as M1–M6 are actually built. Update this file when they do; don't let it drift from reality.

```mermaid
flowchart TB
    Internet((Internet))
    CF["CloudFront<br/>+ AWS WAF managed rules"]
    S3["S3 — private, OAC<br/>/images/*"]
    ALB["ALB — public subnets<br/>/api/* — locked to CloudFront"]
    EC2A["EC2 · ASG · AZ-A<br/>app subnet"]
    EC2B["EC2 · ASG · AZ-B<br/>app subnet"]
    RDS[("RDS PostgreSQL<br/>Multi-AZ · data subnet")]
    Redis[("ElastiCache Redis<br/>data subnet")]

    Internet --> CF
    CF -->|"/images/*"| S3
    CF -->|"/api/*"| ALB
    ALB --> EC2A
    ALB --> EC2B
    EC2A --> RDS
    EC2B --> RDS
    EC2A --> Redis
    EC2B --> Redis
```

**Cross-cutting, not shown above** (full breakdown in `PLAN.md` §5):

| Observability | Security | Resilience |
|---|---|---|
| CloudWatch metrics + logs | IAM least privilege | AWS Backup + cross-region copy |
| Alarms → SNS → email | Secrets Manager + rotation | AWS FIS experiments |
| Synthetics canary | SSM Session Manager | SSM Automation runbooks |
| SLO dashboard | CloudTrail, GuardDuty | Automated restore testing |

Everything above is provisioned by Terraform; both environments are ephemeral.
