# ADR-007: ASG target tracking on CPU now, `ALBRequestCountPerTarget` once M4 exists

**Status:** accepted   **Date:** 2026-09-09   **Milestone:** M3

## Context

`PLAN.md` §6 calls for target tracking on `ALBRequestCountPerTarget` plus a CPU policy — the
honest scaling signal for an API is how much request traffic each instance is actually
carrying, not just how hot its CPU runs, and it demonstrates far better under a load test
than a CPU-only policy would. But `ALBRequestCountPerTarget` is only computable once a target
group exists to count requests against, and the ALB is M4's scope, not M3's.

## Decision

The ASG (`terraform/modules/compute`) gets a `TargetTrackingScaling` policy on
`ASGAverageCPUUtilization` (target 60%) now. The `ALBRequestCountPerTarget` policy is deferred
to M4, added alongside the target group itself once there's a real `resource_label` to point
it at — not faked with a placeholder ARN today.

## Alternatives considered

- **CPU-only, permanently** — simpler, and the more common default. Rejected per `PLAN.md`'s
  own reasoning: a Go API doing mostly I/O (Postgres/Redis/S3 calls) can run hot on request
  count while its CPU stays idle, so CPU alone under-reacts to real load. Kept only as this
  milestone's temporary state, not the end goal.
- **Step scaling** — more manual tuning (explicit thresholds and step sizes) for no benefit
  over target tracking's self-adjusting behavior here.

## Consequences

- Until M4, this ASG only ever scales on CPU — acceptable, since there's no ALB routing real
  traffic to it yet for a request-count signal to mean anything.
- M4 must add the second policy, not replace this one — the plan is both policies running
  together (a target tracking group can hold more than one metric), matching `PLAN.md`'s
  original "target tracking on `ALBRequestCountPerTarget` **+ CPU** policy" wording.
