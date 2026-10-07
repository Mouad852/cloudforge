# ADR-007: ASG target tracking on CPU now, `ALBRequestCountPerTarget` once M4 exists

**Status:** accepted   **Date:** 2026-09-09   **Milestone:** M3

## Context

Target tracking can use `ALBRequestCountPerTarget` alongside CPU — the honest scaling signal
for an API is how much request traffic each instance is actually carrying, not just how hot its
CPU runs, and it demonstrates far better under a load test
than a CPU-only policy would. But `ALBRequestCountPerTarget` is only computable once a target
group exists to count requests against, and the ALB is M4's scope, not M3's.

## Decision

The ASG (`terraform/modules/compute`) gets a `TargetTrackingScaling` policy on
`ASGAverageCPUUtilization` (target 60%) now. The `ALBRequestCountPerTarget` policy is deferred
to M4, added alongside the target group itself once there's a real `resource_label` to point
it at — not faked with a placeholder ARN today.

## Alternatives considered

- **CPU-only, permanently** — simpler, and the more common default. Rejected because a Go API
  doing mostly I/O (Postgres/Redis/S3 calls) can run hot on request
  count while its CPU stays idle, so CPU alone under-reacts to real load. Kept only as this
  milestone's temporary state, not the end goal.
- **Step scaling** — more manual tuning (explicit thresholds and step sizes) for no benefit
  over target tracking's self-adjusting behavior here.

## Consequences

- Until M4, this ASG only ever scales on CPU — acceptable, since there's no ALB routing real
  traffic to it yet for a request-count signal to mean anything.
- Target tracking groups can carry more than one metric, so request-count and CPU policies can
  operate together rather than replacing one another.

> **Status update (2026-10-03):** the `ALBRequestCountPerTarget` policy was never added. M4
> through M10 shipped with the CPU policy alone (`aws_autoscaling_policy.cpu_target_tracking`,
> target 60%), and prod runs one instance with a maximum of two. Whether CPU alone reacts in
> time is evaluated through the E3 load test. The report records a generator-bounded result;
> it does not claim that CPU under-reacted.
