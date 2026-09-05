# Diagrams

Versioned as Mermaid (renders natively on GitHub, diffs like text) so they live in the repo rather than in an external tool nobody else can open. A `.drawio` source is used only where Mermaid genuinely can't express the layout.

| Diagram | File | Produced in | Status |
|---|---|---|---|
| High-level architecture | `architecture-high-level.md` | Planning | ✅ drafted from PLAN.md §5 |
| Network / VPC | `network-vpc.md` | M1 | not yet |
| Traffic flow (CDN → ALB → ASG) | `traffic-flow.md` | M4 | not yet |
| Security flow (WAF, security groups, IAM boundaries) | `security-flow.md` | M10 | not yet |
| Data flow (cache-aside, S3 upload path) | `data-flow.md` | M6 | not yet |
| DR / recovery flow | `dr-recovery-flow.md` | M11 | not yet |

Update the relevant diagram in the same commit as the implementation it describes. A diagram that lags the actual code is worse than no diagram — it actively misleads a reader.
