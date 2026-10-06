# Experiment E2 — Redis reboot under load

**Status:** two measured runs completed 2026-10-06.
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
`/api/products`. The first run used the normal thresholds and stopped during the reboot; the
second run used `k6 --no-thresholds` and continued through recovery for the full 5m30s.

## Timeline (UTC)

| Time (UTC) | Event |
|---|---|
| 2026-10-06 15:31:11.702 | Cache reboot requested |
| 2026-10-06 15:31:40.214 | ElastiCache event: cache node `0001` restarted |
| 2026-10-06 15:32:45.351 | Cache cluster returned to `available` |
| 2026-10-06 15:39:36 | Second reboot requested (CloudTrail) |
| 2026-10-06 15:40:18.899 | Second ElastiCache restart event |
| 2026-10-06 15:44:31 (approx.) | Second 5m30s k6 run completed with no failed requests |

## Measurements

- k6 total requests / failed / error rate: first run `167 / 0 / 0%`; second full run
  `659 / 0 / 0%`.
- Aggregate p95 / maximum latency: first run `763.17 ms` / `3699.23 ms`; second full run
  `677.23 ms` / `6452.45 ms`. The second run includes both reboot and post-recovery traffic;
  phase-separated percentiles were not exported.
- Cache recovery time: `93.65s` from the first reboot request to `available`; `65.14s` from
  the first ElastiCache restart event to `available`. The second run confirms continued HTTP 200
  responses through completion, but its exact `available` polling timestamp was not captured.
- Error-budget consumption: `0` failed requests in both captured samples; these short runs are
  not a monthly-budget calculation.
- Fallback-to-Postgres evidence: all `/api/products` checks remained HTTP 200 during the
  reboot window, consistent with the application serving through the database fallback.

## What surprised me

Redis reboot caused noticeable latency spikes, including a 6.45s maximum in the full run, but the
application returned no 5xx responses while the only cache node restarted or recovered.

## What I changed as a result

No configuration change was made. The result supports keeping Redis as a cache-aside optimisation
and PostgreSQL as the source of record. The latency impact should remain visible in the operational
dashboards even though availability stayed intact.

## Evidence

K6 summary: `C:\Users\user\cloudforge-e2-20261006T153016Z\k6-summary.json`.
K6 per-request CSV: `C:\Users\user\cloudforge-e2-20261006T153016Z\k6-metrics.csv`.
ElastiCache event: `Cache node 0001 restarted` at `2026-10-06T15:31:40.214Z`.
Second k6 summary: `C:\Users\user\cloudforge-e2-20261006T153901Z\k6-summary.json`.
Second k6 per-request CSV: `C:\Users\user\cloudforge-e2-20261006T153901Z\k6-metrics.csv`.
Second ElastiCache event: `Cache node 0001 restarted` at `2026-10-06T15:40:18.899Z`.
A CloudWatch graph was not captured during these runs. See ADR-019 and the Redis runbooks.
