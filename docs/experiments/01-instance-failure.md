# Experiment E1 — Instance failure, one instance versus two

**Status:** prepared, not run.
**Environment:** prod during Session A

## Hypothesis

With the normal one-instance ASG, terminating the sole in-service instance creates an observable
outage until its replacement is healthy. With two instances temporarily in service, the same
termination should produce no client-visible 5xx responses. This measures the cost trade-off in
`PLAN.md` §6.2; it is not comparable with M3's historical two-instance, no-load result.

## Method

Run steady k6 traffic against `/api/products`, identify one in-service instance in
`prod-cloudforge-app`, and inject the fault with:

```bash
aws autoscaling terminate-instance-in-auto-scaling-group --region eu-west-3 \
  --instance-id <instance-id> --no-should-decrement-desired-capacity
```

Run once at desired capacity 1, then once after temporarily setting desired capacity 2 and
confirming both targets are healthy. Restore the ASG's desired capacity to 1 in the same session.
Capture the ASG activity, alarm transitions, k6 summary and a CloudWatch graph spanning each run.

## Timeline (UTC)

| Time | Event |
|---|---|
| | One-instance run: fault introduced |
| | One-instance run: detection and recovery |
| | Two-instance run: fault introduced |
| | Two-instance run: detection and recovery |

## Measurements

- One-instance outage window and failed requests:
- Two-instance failed requests:
- Detection and recovery time for each run:
- Error-budget consumption:
- ASG capacity restored to 1:

## What surprised me

Pending the run.

## What I changed as a result

Pending the run.

## Evidence

Pending: one CloudWatch graph per run and the k6 summaries. See the ASG alarm runbook and
ADR-019.
