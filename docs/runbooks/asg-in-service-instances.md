# Runbook — ASG in-service instance count

**Alarm:** `<env>-cloudforge-asg-in-service-instances`
**Fires when:** `GroupInServiceInstances` (minimum over each minute) is below the ASG's `asg_min_size` (1 in both environments) for 2 consecutive minutes. With no data it goes to INSUFFICIENT_DATA, never OK.
**Severity:** Page now — with the current sizing, fewer in-service instances than the
configured size means the app tier is down, not just less redundant.

> **Known defect (found 2026-10-03), fixed in code and applied by `PLAN.md` §9, C1.** Before C1, this alarm
> never received a datapoint: the ASG did not enable group metrics, so
> `GroupInServiceInstances` was never published, and with `treat_missing_data = notBreaching`
> the alarm stayed OK no matter what happened. Its threshold (< 2) also predated the current
> sizing. C1 enables the group metrics, sets the threshold to the ASG's `asg_min_size` and
> treats missing data as missing (INSUFFICIENT_DATA, not OK). Datapoints are now present in
> both environments; until a real failure transition is observed and recorded in `PLAN.md`,
> use `alb-unhealthy-hosts` and `canary-failed` as the corroborating lost-instance signals.

---

## What it means

Both environments run `min_size = 1`, `desired_capacity = 1`, `max_size = 2` (the committed
defaults CI applies; one instance is a cost decision, `PLAN.md` §6.2). With one instance there
is no redundancy floor: an instance that fails outright or is being replaced means no healthy
target until the replacement passes its health check, and the ALB returns 503s meanwhile.

## Likely causes

- One or more instances failed their health check and were terminated by the ASG, and
  the replacement hasn't finished its `health_check_grace_period` (300s) yet.
- An AZ-level impairment took out every instance in one subnet at once.
- A bad launch template (e.g. broken user-data script) is causing new instances to fail
  health checks immediately, so the ASG keeps replacing and re-failing them in a loop.
- Someone manually terminated an instance outside of normal deploy tooling.

## Diagnose

1. **EC2 → Auto Scaling Groups → Activity tab** — read the most recent activity log
   entries; they say exactly why each instance was launched or terminated.
2. **EC2 → Instances**, filtered by the ASG's tag — check actual instance state
   (`running`, `terminated`, `pending`) versus what the target group considers healthy.
3. If instances are launching but immediately failing health checks, connect to one via
   **SSM Session Manager** before it's terminated and check `cloud-init` / user-data logs
   (`/var/log/cloud-init-output.log`) for a startup failure.

## Mitigate

- If it's a transient replacement in progress: wait out the grace period — this often
  self-resolves within a few minutes with no action needed.
- If new instances are stuck in a launch/fail loop: this points at the launch template
  itself (bad AMI, broken user-data, missing IAM permissions) — pause and fix the launch
  template rather than letting the ASG keep burning through failed launches.
- If an entire AZ is impaired: the ASG launches the replacement in the other app subnet.
  Note that the NAT instance and the database both sit in `eu-west-3a`, so losing that AZ
  takes egress and the database with it (`PLAN.md` §6.2).

## Escalate

If the ASG can't get back to its desired capacity after a few replacement cycles (not
just one grace period), stop and investigate the launch template directly — repeatedly
letting the ASG retry a broken template just burns EC2 launches without fixing anything.

## Verify resolved

`GroupInServiceInstances` back to the desired capacity (once group metrics are enabled);
target group's Targets tab shows the instances as `healthy`; recovery email arrives
automatically.

## Related

Directly threatens the Availability SLI in `docs/observability/slo.md` if sustained —
fewer in-service instances means the survivors absorb more load, increasing the odds of
tripping `ec2-cpu` or `alb-latency-p95` next.
