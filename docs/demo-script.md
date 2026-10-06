# CloudForge demo script

Target length: 3–5 minutes. This is a recording plan, not another game day. Use the committed
reports and read-only endpoints; do not terminate a live instance or tear down prod while
recording.

## 0:00–0:20 — The claim

Show the first section of the root README and say:

> CloudForge is a Terraform-managed AWS environment operated through real incidents, measured
> game days and restore drills. The Go API is intentionally small; the operational system and
> evidence are the project.

Point to the canonical [as-built diagram](diagrams/architecture-high-level.md): WAF → ALB →
ASG → PostgreSQL/Redis/S3, with CloudWatch and GitHub OIDC around it.

## 0:20–0:55 — Reproducibility and security

Show the repository tree, `.github/workflows/terraform.yml`, and the Terraform module layout.
Mention that dev and prod share modules but use separate state, CI uses GitHub OIDC rather than
long-lived AWS keys, and checks include Terraform tests, Checkov, TFLint and drift detection.

## 0:55–1:35 — The real incident

Open the [password-rotation incident review](incidents/2026-09-30-db-password-rotation.md).
Explain the sequence in one sentence: RDS rotated its AWS-managed password, the application
cached the old value, shallow health checks stayed green, and the canary exposed the outage.
Show the fix and the forced-rotation verification rather than replaying the outage.

## 1:35–2:25 — Measured resilience

Open the [experiment index](experiments/README.md) and briefly show the results:

- E1: one instance produced 3 HTTP 503s during replacement; two instances produced 0 failures.
- E2: two Redis reboot runs produced 0 failed requests; p95 was 763ms and 677ms.
- E3: the local generator delivered 224.11 req/s at p95 51.09ms with 0 errors; it was the
  bottleneck, so no application saturation claim is made.
- E4: a rolling refresh completed in 344s with 0 failed requests in the k6 gate.

Use the reports as the source of truth; do not present short game-day samples as an SLO.

## 2:25–3:10 — Recovery boundary

Show the [DR strategy](disaster-recovery/strategy.md) and [E6 report](experiments/06-full-rebuild.md).
State the boundary plainly: the final RDS snapshot restores PostgreSQL rows, while planned
teardown intentionally removes S3 images, artifacts and logs. The measured point-in-time drill
reached `MARKER_FOUND=1` in 1,141s, and the E6 rebuild phase took about 31m12s before `/readyz`
reported PostgreSQL and Redis `ok`.

## 3:10–3:45 — Cost and trade-offs

Show [cost analysis](cost-analysis.md): prod averaged about `$2.93/day` during the measured
window, and the Free-plan credit was `$44.11` on 2026-10-06. Explain the deliberate compromises:
single-AZ RDS, one Redis node, one app instance at rest, NAT instance, and backup/restore instead
of a duplicate always-on stack.

## 3:45–4:00 — Close

End on the root README's evidence table and say:

> The important result is not that every experiment passed. It is that failures, capacity
> limits, recovery boundaries and costs are measured, linked to code, and recorded honestly.

## Recording checklist

- [ ] Hide credentials, account IDs, secret values and personal terminal paths.
- [ ] Use the committed reports and read-only output; do not show raw Terraform state.
- [ ] Keep the canary error-budget result and the E3 generator limitation visible.
- [ ] Link the published recording from the root README only after reviewing it once.
