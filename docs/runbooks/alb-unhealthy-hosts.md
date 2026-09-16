# Runbook — ALB unhealthy hosts

**Alarm:** `dev-cloudforge-alb-unhealthy-hosts`
**Fires when:** `UnHealthyHostCount` ≥ 1 for 2 consecutive minutes, on the blue target group.
**Severity:** Page now — this is one leg of the `service-degraded` composite alarm.

---

## What it means

The ALB's health checker (path-based, hits the app's `/readyz`) has marked at least one
EC2 instance behind the blue target group as unable to serve traffic. The ALB stops
routing to that instance immediately — this alarm is about *reduced redundancy*, not
necessarily *downtime*, since the ASG's `min_size = 2` means at least one other instance
should still be healthy.

## Likely causes

- The instance's `/readyz` endpoint is failing its own dependency checks (RDS or Redis
  unreachable) — see `docs/troubleshooting` / M6's Redis TLS incident for the exact shape
  of this failure.
- A fresh instance from a launch-template rollout or instance refresh hasn't finished
  its `health_check_grace_period` (300s) yet — check whether this coincides with a
  deploy before assuming an incident.
- The instance itself is unreachable (crashed, OOM, kernel panic) — no traffic being
  served at all, not just a failing check.

## Diagnose

1. **EC2 → Target Groups → blue-tg → Targets tab** — confirm which instance(s) are
   unhealthy and read the "Health check details" reason string directly; it usually
   names the failing check.
2. **CloudWatch → Logs → `/cloudforge/dev/app` → Logs Insights** — filter to the
   unhealthy instance's ID (visible in the target group) and look for `level=ERROR`
   around the time the alarm fired.
3. Connect via **SSM Session Manager** (no bastion, no SSH key — ADR-005) and check the
   process is actually running: `systemctl status cloudstore-api` (or equivalent), then
   `curl localhost:8080/readyz` locally to see the real error the ALB can't see.

## Mitigate

- If it's one instance and the ASG has capacity: let the ASG's own health check replace
  it automatically, or manually terminate the instance from **EC2 → Instances** to force
  a replacement — the ASG will launch a new one from the current launch template.
- If it's *every* instance: this is a shared dependency (RDS, Redis, or a bad AMI/launch
  template), not a single bad host — stop replacing instances one at a time and go
  straight to diagnosing the shared dependency (check `rds-*` and `redis-*` alarms too).
- If a deploy is in progress and this is the grace-period window, wait it out before
  taking action — 300 seconds is the expected window, not a failure.

## Escalate

If replacing the instance doesn't clear the alarm within ~10 minutes, or every instance
in the ASG is failing the same check, the problem is upstream of compute (RDS/Redis/
networking) — stop working this runbook and move to the relevant RDS/Redis runbook.

## Verify resolved

Target group's Targets tab shows all instances `healthy`; the alarm's own `ok_actions`
sends a recovery email to the SNS topic automatically — no separate check needed.

## Related

Half of the `service-degraded` composite alarm (paired with `alb-5xx`). See
`docs/observability/slo.md` for how this maps to the Availability SLO.
