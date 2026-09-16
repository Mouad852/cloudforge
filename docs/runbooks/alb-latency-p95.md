# Runbook — ALB latency (p95)

**Alarm:** `dev-cloudforge-alb-latency-p95`
**Fires when:** p95 `TargetResponseTime` above 1 second, sustained for 5 minutes.
**Severity:** Investigate soon — not paired into the composite alarm, so a single trip is
a warning, not automatically a full incident.

---

## What it means

`TargetResponseTime` measures the ALB's own view of how long the target took to respond
— network time to/from the client isn't included. A sustained p95 above 1s means the
*slowest 5%* of requests are meaningfully slow, not that everything is slow; check the
average and p99 alongside p95 (all three are plotted on the Golden Signals dashboard's
Latency widget) to see how widespread it is.

## Likely causes

- A slow downstream call — RDS query without an index, or Redis miss forcing a slow
  origin fetch — check `rds-cpu` / `rds-connections` for correlated saturation.
- CPU saturation on the instances themselves (`ec2-cpu` alarm) causing request queueing.
- A specific expensive endpoint being hit disproportionately (e.g. an unpaginated list
  query) — check access patterns in the app logs.
- Cold-start effect right after an instance refresh, before OS/app caches warm up.

## Diagnose

1. **CloudWatch → Metrics → AWS/ApplicationELB → TargetResponseTime** — compare Average,
   p95, and p99 side by side to judge how widespread the slowdown is.
2. **CloudWatch → Logs Insights** on `/cloudforge/dev/app` — if the app logs per-request
   duration, filter for the slowest requests in the window and see which route dominates.
3. Check `rds-cpu`, `rds-connections`, `ec2-cpu` for the same window — latency is very
   often a symptom of saturation elsewhere, not a problem in the ALB layer itself.

## Mitigate

- If it's one slow query: this is an app-level fix (add an index, cache the result) —
  not something to firefight at the infrastructure layer in the moment.
- If it's fleet-wide CPU saturation: target tracking scaling (ADR-007) should already be
  adding capacity — confirm the ASG is actually scaling out (**EC2 → Auto Scaling
  Groups → Activity tab**) rather than stuck at its current size.
- If it's RDS saturation: see `rds-cpu` / `rds-connections` runbooks.

## Escalate

If latency keeps climbing despite the ASG scaling out (i.e. more instances aren't
helping), the bottleneck is a shared resource (RDS, Redis) that horizontal app scaling
can't fix — move to the relevant data-tier runbook instead of adding more compute.

## Verify resolved

p95 `TargetResponseTime` drops back under 1s; recovery email arrives automatically.

## Related

Feeds the Latency SLI in `docs/observability/slo.md` — note the SLO threshold (p99 <
500ms, 30-day rolling) is stricter than this alarm's operational threshold (p95 > 1s,
5-minute window) on purpose; see the "Alarms are not the same thing as SLOs" section
there for why.
