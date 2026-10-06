# Service Level Objectives

Defined in M7, before any M12 game day (ADR-020). Every chaos experiment measures its
damage against the numbers on this page — not the other way around.

All three SLIs are measured from **outside** the application: the Synthetics canary
(`<env>-api-avail`, hitting the ALB directly since ADR-025) and the ALB's own metrics. Nothing here reads the
app's own view of itself, because the app's view is exactly what's unavailable during the
failures these SLOs exist to catch — a service that has crashed cannot self-report that it
has crashed.

## SLIs

| SLI | Definition | Measured by |
|---|---|---|
| Availability | successful canary runs ÷ total canary runs | `CloudWatchSynthetics` → `SuccessPercent`, dimension `CanaryName = <env>-api-avail` |
| Latency | proportion of requests with `TargetResponseTime` < 500 ms | `AWS/ApplicationELB` → `TargetResponseTime`, `p99` |
| Correctness | proportion of responses that are not 5xx | `AWS/ApplicationELB` → `HTTPCode_Target_5XX_Count` ÷ `RequestCount` (metric-math) |

All three are plotted live on the SLO dashboard (`<env>-slo` in CloudWatch → Dashboards),
each against a horizontal line marking its target below.

## SLOs (30-day rolling)

| Objective | Target | Monthly error budget |
|---|---|---|
| Availability | 99.5% | 3h 39m of downtime |
| Latency (p99 < 500 ms) | 99% | 1% of requests may be slow |
| Correctness | 99.9% | 0.1% of requests may 5xx |

These are a **starting proposal** (from the original plan, ADR-020), not a permanent contract. Once the canary
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

## Current status (2026-10-06)

The canary has hit the ALB directly since ADR-025 (2026-09-22; CloudFront was denied), so
`SuccessPercent` carries real samples in both environments. Until 2026-10-02 it only fed the
dashboard; the `<env>-cloudforge-canary-failed` alarm now pages on it
(`docs/runbooks/canary-failed.md`).

**The prod availability budget is exhausted.** The 2026-09-30 database password rotation
outage (`docs/incidents/2026-09-30-db-password-rotation.md`) failed every canary run for about
40 hours, against a monthly budget of about 3.6 hours. The 30-day window clears around
2026-10-31. Under the policy above this is a deploy freeze with reliability work only. M12's
game days count as reliability work, so they go ahead, and each records the budget it consumes.

The measured snapshot below is the M13 error-budget report; future monthly windows should be
appended rather than replacing this incident-inclusive baseline.

## Measured error-budget snapshot (2026-09-29 through 2026-10-06)

CloudWatch `CloudWatchSynthetics/SuccessPercent` for `prod-api-avail` returned 2,231 samples
from `2026-09-29T00:00:00Z` through `2026-10-07T00:00:00Z`. Weighted by each hourly sample
count, 1,746 were successful and 485 failed: **78.26% availability**. The failures are
dominated by the approximately 40-hour database-password rotation outage documented in the
incident review; the remaining samples were 100% except for the rebuild window's partial hour.

The 99.5% availability objective allowed about 11 failed samples in this observation window, so
the budget was exhausted by the incident. `AWS/ApplicationELB` had no datapoints for
`HTTPCode_Target_5XX_Count` for the same prod ALB and period; that is recorded as **no ALB
5xx data**, not as proof of zero errors. The k6 game-day reports remain the authoritative
request-level evidence for E1–E4.

## See also

- ADR-020 (`docs/adr/020-slos-before-gamedays.md`) — why these are defined now, not in M12.
- ADR-025 (`docs/adr/025-cloudfront-denied-edge-redesign.md`) — why the canary targets the
  ALB (ADR-014's CloudFront-only lockdown is superseded).
- `PLAN.md` §10 — the measurements table that game-day results are filled into.
