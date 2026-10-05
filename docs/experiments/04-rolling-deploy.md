# Experiment E4 — Rolling deployment under load

**Status:** prepared, not run.
**Environment:** prod during Session A

## Hypothesis

The current launch-before-terminate rolling deployment path keeps the API available under the
bounded k6 gate. The target is zero failed requests; the 198 errors observed before the
2026-09-25 ordering fix are historical baseline evidence, not an expected result.

## Method

Run the normal deployment mechanism while k6 traffic is active:

```bash
K6_DURATION=8m scripts/deploy.sh prod
```

Record the launch-template version, instance-refresh ID, each refresh state transition, k6 summary
and one CloudWatch graph spanning the rollout. If the deploy gate reports a failed request, stop,
investigate and do not present the rollout as zero-downtime.

## Timeline (UTC)

| Time | Event |
|---|---|
| | k6 gate started |
| | Instance refresh started |
| | Replacement healthy |
| | Old instance terminated |
| | k6 gate completed |

## Measurements

- k6 total requests / failed / error rate:
- Rollout duration and phase durations:
- ALB 5xx count:
- Error-budget consumption:
- Comparison with the 198-error historical baseline:

## What surprised me

Pending the run.

## What I changed as a result

Pending the run.

## Evidence

Pending: one CloudWatch graph and the k6 summary. The existing 2026-09-25 evidence is retained in
ADR-026.
