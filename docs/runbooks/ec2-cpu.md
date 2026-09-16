# Runbook — EC2 fleet CPU saturation

**Alarm:** `dev-cloudforge-ec2-cpu`
**Fires when:** fleet-average `CPUUtilization` above 80%, sustained for 10 minutes.
**Severity:** Investigate soon — target tracking scaling (ADR-007) should already be
responding; this alarm is the "did it actually work" check.

---

## What it means

The ASG has a target-tracking scaling policy (ADR-007) that's supposed to add capacity
automatically before CPU gets this hot. This alarm firing means either scaling hasn't
kicked in yet (it lags real usage by design), or the ASG is already at `max_size = 6` and
has nowhere left to scale to.

## Likely causes

- A genuine traffic spike — check the Golden Signals dashboard's Traffic widget
  (`RequestCount`) for the same window to confirm.
- Scaling is lagging normally — target tracking reacts to a rolling average, not
  instantaneously, so a brief spike can trip this alarm before a scale-out finishes.
- The ASG is already at max capacity (6 instances) and load has outgrown it entirely.
- A single runaway process on one or more instances (not real traffic) — check whether
  CPU is evenly spread across instances or concentrated on one.

## Diagnose

1. **EC2 → Auto Scaling Groups → Activity tab** — confirm whether a scale-out activity
   is already in progress or recently completed.
2. **CloudWatch → Metrics → AWS/EC2 → CPUUtilization**, split by instance ID (not just
   the ASG average) — even load across all instances points at real traffic; one hot
   instance points at something instance-specific.
3. Check the Golden Signals dashboard's Traffic widget to correlate with `RequestCount`.

## Mitigate

- If scaling is in progress: let it finish — this is the expected, self-healing path and
  usually needs no manual action.
- If already at `max_size`: this is a capacity ceiling, not a transient issue — either
  the traffic is a real, sustained increase (raise `asg_max_size`) or it's abnormal
  (investigate before scaling further, since more capacity won't fix a runaway process).
- If CPU is concentrated on one instance: terminate that instance and let the ASG
  replace it, same as the `asg-in-service-instances` runbook.

## Escalate

If CPU stays pinned at max capacity with the ASG already at 6 instances, this needs a
capacity-planning decision (raise `asg_max_size`, or a bigger instance type), not another
attempted quick fix — see `docs/resilience/capacity-planning.md`.

## Verify resolved

Fleet-average `CPUUtilization` back under 80%; recovery email arrives automatically.

## Related

Feeds the Saturation panel of the Golden Signals dashboard. Sustained CPU saturation is
usually what drives `alb-latency-p95` next — check that alarm too if this one has been
firing for a while.
