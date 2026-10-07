# Diagrams

The Mermaid source remains in this repository so it can be reviewed and updated as text. The rendered diagrams below are versioned assets used as the reader-facing overview; the source is kept in a collapsed section on its page. The Network / VPC view is the intentional image-only exception because its route-table relationships are clearer as an illustrated layout.

| Diagram | File | Rendered asset | Status |
|---|---|---|---|
| High-level architecture (canonical) | `architecture-high-level.md` | `assets/architecture-high-level-generated-v2.png` | ✅ as-built (`PLAN.md` §4) |
| Network / VPC | `network-vpc.md` | `assets/network-vpc-generated.png` | ✅ as-built |
| Traffic flow (WAF → ALB → ASG) | `traffic-flow.md` | `assets/traffic-flow-generated.png` | ✅ as-built (ADR-025), verified 2026-09-25 |
| Security request path | `security-flow.md` §1 | `assets/security-request-path-generated.png` | ✅ as-built, drawn 2026-10-02 |
| Security identity path | `security-flow.md` §2 | `assets/security-identity-path-generated.png` | ✅ as-built, drawn 2026-10-02 |
| Data flow (cache-aside, S3 image path) | `data-flow.md` | `assets/data-flow-generated.png` | ✅ as-built (ADR-025), verified 2026-09-25 |
| DR / recovery flow | `../disaster-recovery/strategy.md` | `assets/disaster-recovery-flow-generated.png` | ✅ as-built |

Update the relevant diagram in the same commit as the implementation it describes. A diagram that lags the actual code is worse than no diagram — it actively misleads a reader.
