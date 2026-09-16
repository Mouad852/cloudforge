# Service Level Objectives

Defined in M7, before any M12 game day (ADR-020). Every chaos experiment measures its
damage against the numbers on this page — not the other way around.

All three SLIs are measured from **outside** the application: the Synthetics canary
(`dev-api-avail`, hitting CloudFront) and the ALB's own metrics. Nothing here reads the
app's own view of itself, because the app's view is exactly what's unavailable during the
failures these SLOs exist to catch — a service that has crashed cannot self-report that it
has crashed.

## SLIs

| SLI | Definition | Measured by |
|---|---|---|
| Availability | successful canary runs ÷ total canary runs | `CloudWatchSynthetics` → `SuccessPercent`, dimension `CanaryName = dev-api-avail` |
| Latency | proportion of requests with `TargetResponseTime` < 500 ms | `AWS/ApplicationELB` → `TargetResponseTime`, `p99` |
| Correctness | proportion of responses that are not 5xx | `AWS/ApplicationELB` → `HTTPCode_Target_5XX_Count` ÷ `RequestCount` (metric-math) |

All three are plotted live on the SLO dashboard (`dev-slo` in CloudWatch → Dashboards),
each against a horizontal line marking its target below.

## SLOs (30-day rolling)

| Objective | Target | Monthly error budget |
|---|---|---|
| Availability | 99.5% | 3h 39m of downtime |
| Latency (p99 < 500 ms) | 99% | 1% of requests may be slow |
| Correctness | 99.9% | 0.1% of requests may 5xx |

These are a **starting proposal** (PLAN.md §10), not a permanent contract. Once the canary
has run for long enough to produce a real baseline, these numbers get revisited — and if
they change, the reason for the change is written down here, not silently edited away.

## Error budget policy

Followed during M12's game days, not just referenced:

- **Budget > 50% remaining** → ship freely, run experiments.
- **Budget < 50%** → no new experiments until the cause is understood.
- **Budget exhausted** → deploy freeze; reliability work only, until the 30-day window
  rolls forward and budget is restored.

The point of writing this down in advance is that it turns "should we run today's
experiment" into a lookup instead of a judgment call made under pressure.

## Alarms are not the same thing as SLOs

The M7 alarm set (`terraform/modules/observability/alarms.tf`) and the SLOs above both
watch overlapping metrics, but they answer different questions, and their numbers are
deliberately not identical:

| | Alarms | SLOs |
|---|---|---|
| Question | "Is something wrong *right now*?" | "Did we honor our promise *this month*?" |
| Window | Minutes (e.g. p95 latency > 1s for 5 min) | 30 days, rolling |
| Example | `alb-latency-p95`: pages if p95 > 1s, sustained 5 minutes | Latency SLO: 99% of requests p99 < 500ms over 30 days |
| Purpose | Wake a human up fast enough to act | Report whether the service met its target over time |

An alarm firing doesn't automatically mean the SLO is at risk — a single 6-minute spike
can trip the `alb-latency-p95` alarm and barely dent a 30-day error budget. The alarms are
the smoke detector; the SLOs are the monthly inspection report.

## Current status

The canary and both dashboards are built and deployed (M7), but the canary targets the
CloudFront domain per ADR-014 (the ALB rejects anything not arriving through CloudFront),
and CloudFront itself is not live yet — blocked on an open AWS Support case, tracked
separately from M7. Until that's resolved, `SuccessPercent` has no real samples to report.
Once CloudFront is live, the canary starts producing genuine data immediately (its 5-minute
schedule was already running), and the first real error-budget numbers get recorded in
PLAN.md §11's measurements table starting with M12's first experiment.

## See also

- ADR-020 (`docs/adr/020-slos-before-gamedays.md`) — why these are defined now, not in M12.
- ADR-014 (`docs/adr/014-alb-locked-to-cloudfront.md`) — why the canary must target
  CloudFront, not the ALB directly.
- PLAN.md §10 — the original proposal these numbers are copied from.
- PLAN.md §11 — where measured game-day numbers get filled in against this budget.
