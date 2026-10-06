# Experiment E4 — Rolling deployment under load

**Status:** completed 2026-10-06.
**Environment:** prod, eu-west-3 (Session A)

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

| Time (UTC) | Event |
|---|---|
| 2026-10-06 16:29:28 | Launch-template version 11 created (`deploy-752698d`) |
| 2026-10-06 16:29:37 | Instance refresh `451f28df-1e51-406c-98f3-4f4b896284a6` started |
| 2026-10-06 16:35:21 | Instance refresh became `Successful` |
| 2026-10-06 16:37:31 | 8-minute k6 gate completed |
| 2026-10-06 16:37:31 | Final ASG state: one `InService`/`Healthy` instance |

## Measurements

- k6 total requests / failed / error rate: `2179 / 0 / 0%`.
- Rollout duration and phase durations: instance refresh `344s` (5m44s); k6 gate `8m00.8s`.
- ALB 5xx count: no 5xx responses were observed by k6; the targeted CloudWatch 5xx query
  returned no datapoints for the rollout window.
- Error-budget consumption: `0` failed requests in the deploy-gate sample.
- Comparison with the 198-error historical baseline: `0` current failures versus `198`
  historical failures before the launch-before-terminate ordering fix.
- Latency: p95 `664.13 ms`, maximum `916.15 ms`; the deploy gate checked failure rate only,
  so this latency observation is recorded separately from its pass/fail result.

## What surprised me

The rollout had zero failed requests, but p95 reached `664.13 ms` even with only five VUs. The
launch-before-terminate strategy protected correctness while still allowing a measurable latency
increase during the refresh.

## What I changed as a result

No configuration change was made. The successful refresh confirms the current replacement order
and 100% healthy-capacity preference are effective for this workload; latency should remain a
separate operational signal.

## Evidence

Evidence: instance-refresh ID `451f28df-1e51-406c-98f3-4f4b896284a6`, launch-template version
11 (`deploy-752698d`), and the k6 summary pasted above. The final ASG check showed one healthy
instance. No CloudWatch graph was captured; the existing 2026-09-25 evidence is retained in
ADR-026.
