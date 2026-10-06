# Experiment E3 — Load and scaling

**Status:** completed 2026-10-06; generator-bounded result.
**Environment:** prod, eu-west-3 (Session A)

## Hypothesis

One `t4g.small` can meet the latency and error targets only up to a measurable arrival rate. At
sustained CPU pressure, target tracking at 60% should request a second instance; the test must
separate application saturation from a limited load generator.

## Method

Run the arrival-rate benchmark only through the bounded WAF exemption window:

```bash
scripts/waf-benchmark-window.sh prod --max-minutes 30 -- k6 run scripts/capacity-test.js
```

The window records its open/close timestamps, verifies the IP-set cleanup, and samples generator
CPU. Stop at the first sustained p95 >= 500 ms or error rate >= 1%. If generator CPU reaches 85%
or k6 reports dropped iterations, report the generator as the bottleneck instead of claiming an
application capacity number.

## Timeline (UTC)

| Time (UTC) | Event |
|---|---|
| 2026-10-06 16:01:58 | WAF exemption window opened |
| 2026-10-06 16:02:06 | Exemption active and verified |
| 2026-10-06 16:03:06 | Load ramp started |
| 2026-10-06 16:23:07 | Ramp reached 400 req/s target; generator reported 609 dropped iterations |
| 2026-10-06 16:23:15 | Exemption removed and verified empty |
| 2026-10-06 16:23:17 | WAF lock token unchanged; window closed |

## Measurements

- Highest sustainable requests/second at the p95 target: not measured; the generator delivered
  `224.11 req/s` while the application remained below the latency and error targets.
- First sustained breach and bottleneck: no application SLO breach; k6 dropped `609` iterations
  while targeting `400 req/s`, so the load generator was the limiting component.
- Generator CPU peak and dropped iterations: `33%` CPU peak; `609` dropped iterations; k6 reached
  its `500` VU ceiling.
- Scale-out request and time to second healthy target: no scale-out result was captured during
  this generator-bounded run.
- Error-budget consumption: `0` failed requests out of `268,940` (`0%`).

## What surprised me

The generator could not sustain the requested `400 req/s` even though its CPU peaked at only 33%:
it reached 500 VUs and dropped 609 iterations. That is a generator/runtime ceiling, not evidence
that CloudForge saturated.

## What I changed as a result

No infrastructure change was made. The result is reported as a lower bound: CloudForge handled
the `224.11 req/s` actually delivered with p95 `51.09 ms` and zero errors, but a stronger or
distributed generator is required to measure the application's saturation point.

## Evidence

Evidence directory:
`C:\Users\user\cloudforge-benchmarks\prod-20261006T155751Z`.
The timeline records the WAF open/close and cleanup, `benchmark.log` contains the k6 summary,
and `generator-cpu.csv` records the 33% peak. No CloudWatch graph was captured during this run.
This report feeds `docs/resilience/capacity-planning.md` in M13.
