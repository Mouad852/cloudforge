# Diagrams

Versioned as Mermaid (renders natively on GitHub, diffs like text) so they live in the repo rather than in an external tool nobody else can open. A `.drawio` source is used only where Mermaid genuinely can't express the layout.

| Diagram | File | Produced in | Status |
|---|---|---|---|
| High-level architecture (canonical) | `architecture-high-level.md` | Planning, redrawn as-built 2026-10-03 | ✅ as-built (`PLAN.md` §4) |
| Network / VPC | `network-vpc.md` | M1 | ✅ as-built (generated image, not Mermaid — see file) |
| Traffic flow (WAF → ALB → ASG) | `traffic-flow.md` | M4, redesigned M10 | ✅ as-built (ADR-025), verified 2026-09-25 |
| Security flow (WAF, security groups, IAM boundaries) | `security-flow.md` | M10 | ✅ as-built, drawn 2026-10-02 |
| Data flow (cache-aside, S3 image path) | `data-flow.md` | M6, redesigned M10 | ✅ as-built (ADR-025), verified 2026-09-25 |
| DR / recovery flow | inside `../disaster-recovery/strategy.md` | M11 | not yet — one Mermaid flow in the strategy document, no separate file |

Update the relevant diagram in the same commit as the implementation it describes. A diagram that lags the actual code is worse than no diagram — it actively misleads a reader.
