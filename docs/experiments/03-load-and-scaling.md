# Experiment E3 — Load and scaling

**Status:** prepared, not run.
**Environment:** prod during Session A

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

| Time | Event |
|---|---|
| | WAF exemption opened and verified |
| | Load ramp started |
| | First sustained SLO breach or generator limit |
| | Scaling action and outcome |
| | WAF exemption removed and verified |

## Measurements

- Highest sustainable requests/second at the p95 target:
- First sustained breach and bottleneck:
- Generator CPU peak and dropped iterations:
- Scale-out request and time to second healthy target:
- Error-budget consumption:

## What surprised me

Pending the run.

## What I changed as a result

Pending the run.

## Evidence

Pending: WAF-window timeline, k6 summary, generator CPU sample and one CloudWatch graph. This
report feeds `docs/resilience/capacity-planning.md` in M13.
