# Experiment E2 — Redis reboot under load

**Status:** prepared, not run.
**Environment:** prod during Session A

## Hypothesis

Redis is a cache-aside optimisation, not the data source of record. Rebooting its only node while
traffic reads `/api/products` should increase latency while the cache is unavailable, but should
not produce 5xx responses because the application falls back to PostgreSQL.

## Method

Run bounded k6 traffic against `/api/products`, record the cache cluster ID, and inject the fault
with:

```bash
aws elasticache reboot-cache-cluster --region eu-west-3 \
  --cache-cluster-id <cluster-id> --cache-node-ids-to-reboot 0001
```

Wait for the cache node and application readiness to recover. Record k6 results, CloudWatch Redis
and ALB metrics, relevant alarm transitions and the cache-node recovery time. Do not use `/readyz`
as the k6 path: it intentionally reports Redis down.

## Timeline (UTC)

| Time | Event |
|---|---|
| | Cache reboot requested |
| | Detection: alarm or application signal |
| | Cache node available |
| | Service steady state confirmed |

## Measurements

- k6 total requests / failed / error rate:
- p95 before, during and after the reboot:
- Cache recovery time:
- Error-budget consumption:
- Fallback-to-Postgres evidence:

## What surprised me

Pending the run.

## What I changed as a result

Pending the run.

## Evidence

Pending: one CloudWatch graph spanning the reboot and the k6 summary. See ADR-019 and the Redis
runbooks.
