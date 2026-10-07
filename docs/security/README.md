# Security

CloudForge applies layered controls across identity, network access, data protection, delivery,
and operations.

| Document | Focus |
|---|---|
| [Threat model](threat-model.md) | Threats, mitigations, and explicitly accepted boundaries |
| [Well-Architected review](well-architected.md) | AWS Well-Architected findings, remediations, and constraints |
| [Encryption inventory](encryption-inventory.md) | Encryption at rest and in transit for every data store and network hop |
| [Data classification](data-classification.md) | Data sensitivity, retention, and handling controls |
| [Incident response](incident-response.md) | Severity model, evidence sources, and security-response procedures |
| [GitHub OIDC trust policy](github-oidc-trust-policy.md) | Keyless CI access and trust-boundary design |

Core controls include GitHub OIDC with short-lived AWS credentials, least-privilege workload
roles, SSM-only host access, IMDSv2, private application and data tiers, WAF protection,
encryption at rest and in transit, CloudTrail, VPC Flow Logs, IAM Access Analyzer, Checkov, and
daily drift detection.
