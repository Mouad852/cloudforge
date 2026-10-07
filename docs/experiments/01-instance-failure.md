# Experiment E1 — Instance failure, one instance versus two

**Status:** completed 2026-10-06.
**Environment:** prod, eu-west-3 (Session A)

## Hypothesis

With the normal one-instance ASG, terminating the sole in-service instance creates an observable
outage until its replacement is healthy. With two instances temporarily in service, the same
termination should produce no client-visible 5xx responses. This measures the cost trade-off in
the current one-instance operating mode; it is not comparable with the historical two-instance,
no-load result.

## Method

Run steady k6 traffic against `/api/products`, identify one in-service instance in
`prod-cloudforge-app`, and inject the fault with:

```bash
aws autoscaling terminate-instance-in-auto-scaling-group --region eu-west-3 \
  --instance-id <instance-id> --no-should-decrement-desired-capacity
```

Run once at desired capacity 1, then once after temporarily setting desired capacity 2 and
confirming both targets are healthy. Restore the ASG's desired capacity to 1 in the same session.
The run used a fixed 5 requests/second k6 arrival rate. The one-instance phase ran until the
error threshold stopped it; the two-instance phase likewise stopped when its latency threshold
was exceeded. Capture the ASG activity, alarm state, k6 summary and a CloudWatch graph spanning
each run.

## Timeline (UTC)

| Time (UTC) | Event |
|---|---|
| 2026-10-06 15:10:23 | One-instance k6 load started at 5 req/s |
| 2026-10-06 15:11:12 | One-instance fault introduced against `i-0bdebf097b97c29f5` |
| 2026-10-06 15:11:15–15:11:16 | Three HTTP 503 responses observed; replacement `i-0d9a9093b6aa255be` launched and its ASG launch activity completed at 15:11:25 |
| 2026-10-06 15:15:00 | Desired capacity raised to 2; both instances healthy |
| 2026-10-06 15:15:51 | Two-instance k6 load started at 5 req/s |
| 2026-10-06 15:16:38 | Two-instance fault introduced against `i-0b67325315e279f65` |
| 2026-10-06 15:16:38–15:16:57 | No failed requests; p95 latency crossed 500 ms and k6 stopped. Replacement launched at 15:16:53 |
| 2026-10-06 15:20:26 | Desired capacity restored to 1 |

## Measurements

- One-instance outage window and failed requests: 3 HTTP 503 responses at
  `15:11:15Z`–`15:11:16Z`; k6 recorded 3 failures out of 269 requests (`1.115%`).
- Two-instance failed requests: 0 out of 314 requests (`0%`).
- Detection and recovery time for each run: the one-instance replacement launch activity
  completed 13 seconds after the fault command; the two-instance replacement was launched while
  the surviving instance continued serving. These are ASG activity timings, not a claim that the
  old instance had fully finished its lifecycle hook at that point.
- Latency: one-instance p95 `201.66 ms`; two-instance p95 `623.23 ms`, with no failed requests
  but a short latency spike during replacement.
- Error-budget consumption: the one-instance run had a `1.115%` request-failure rate in its
  short sample; do not treat that small sample as a monthly-budget calculation.
- ASG capacity restored to 1: yes, one healthy instance (`i-0307d5048a2060070`) remained.

## What surprised me

The single-instance run produced real 503s even though the replacement launched quickly. Two
instances prevented failed requests, but the termination still caused a brief latency spike that
crossed the k6 p95 threshold.

## What I changed as a result

The normal desired capacity was restored to 1 after the comparison. The result supports treating
two instances as a deliberate availability trade-off rather than assuming the ASG replacement
path is invisible to clients.

## Evidence

K6 summaries and CSV evidence are stored outside the repository:

- `C:\Users\user\cloudforge-e1-one\k6-summary.json`
- `C:\Users\user\cloudforge-e1-two\k6-summary.json`

ASG activity IDs were `67168447-1342-df67-41fe-22d04ee4e451` (one-instance fault) and
`4f668447-2730-d9b0-8400-2af2eeba5aa1` (two-instance fault). A CloudWatch graph was not
captured during this run; the text summaries and activity history are the available evidence.
See the ASG alarm runbook and ADR-019.
