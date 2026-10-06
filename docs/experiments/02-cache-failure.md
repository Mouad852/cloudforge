# Experiment E2 — Redis reboot under load

**Status:** one measured run completed 2026-10-06; post-recovery load sample pending.
**Environment:** prod, eu-west-3 (Session A)

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
as the k6 path: it intentionally reports Redis down. This run used 2 requests/second against
`/api/products`; the k6 latency threshold stopped the run during the reboot before a
post-recovery sample was collected.

## Timeline (UTC)

| Time (UTC) | Event |
|---|---|
| 2026-10-06 15:31:11.702 | Cache reboot requested |
| 2026-10-06 15:31:40.214 | ElastiCache event: cache node `0001` restarted |
| 2026-10-06 15:32:45.351 | Cache cluster returned to `available` |
| Pending | Post-recovery steady-state load sample |

## Measurements

- k6 total requests / failed / error rate: `167 / 0 / 0%`.
- p95 before, during and after the reboot: aggregate run p95 `763.17 ms`, maximum
  `3699.23 ms`; a separate post-recovery sample is pending because the latency threshold
  stopped k6 during the reboot.
- Cache recovery time: `93.65s` from reboot request to `available`; `65.14s` from the
  ElastiCache restart event to `available`.
- Error-budget consumption: `0` failed requests in the captured sample; the sample is too
  short to convert directly into a monthly budget percentage.
- Fallback-to-Postgres evidence: all `/api/products` checks remained HTTP 200 during the
  reboot window, consistent with the application serving through the database fallback.

## What surprised me

Redis reboot caused a noticeable latency spike, but the application returned no 5xx responses
while the only cache node restarted. The test threshold ended the run before the recovery phase
could be measured under continued load.

## What I changed as a result

No configuration change was made. The result supports keeping Redis as a cache-aside optimisation
and PostgreSQL as the source of record; repeat with thresholds disabled if a before/during/after
latency curve is required.

## Evidence

K6 summary: `C:\Users\user\cloudforge-e2-20261006T153016Z\k6-summary.json`.
K6 per-request CSV: `C:\Users\user\cloudforge-e2-20261006T153016Z\k6-metrics.csv`.
ElastiCache event: `Cache node 0001 restarted` at `2026-10-06T15:31:40.214Z`.
A CloudWatch graph was not captured during this run. See ADR-019 and the Redis runbooks.
