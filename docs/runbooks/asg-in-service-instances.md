# Runbook — ASG in-service instance count

**Alarm:** `dev-cloudforge-asg-in-service-instances`
**Fires when:** `GroupInServiceInstances` < 2, for 2 consecutive minutes.
**Severity:** Page now — the fleet has lost its redundancy floor (`asg_min_size = 2`).

---

## What it means

The ASG is configured with `min_size = 2`, `max_size = 6`, `desired_capacity = 2` — two
instances is the deliberate floor for redundancy across the two app subnets
(`app-a`/`app-b`). Fewer than 2 in-service means either an instance failed outright, or
enough instances are unhealthy/terminating that the ASG hasn't replaced them yet.

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
- If an entire AZ is impaired: this is the scenario M12's "AZ impairment" game day is
  built to test — the other AZ's instance(s) should already be absorbing traffic; confirm
  via the target group's Targets tab.

## Escalate

If the ASG can't get back to 2 in-service instances after a few replacement cycles (not
just one grace period), stop and investigate the launch template directly — repeatedly
letting the ASG retry a broken template just burns EC2 launches without fixing anything.

## Verify resolved

`GroupInServiceInstances` back to 2 (or higher, if scaled out); target group's Targets
tab shows the instances as `healthy`; recovery email arrives automatically.

## Related

Directly threatens the Availability SLI in `docs/observability/slo.md` if sustained —
fewer in-service instances means the survivors absorb more load, increasing the odds of
tripping `ec2-cpu` or `alb-latency-p95` next.
