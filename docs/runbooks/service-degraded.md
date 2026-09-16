# Runbook — Service degraded (composite alarm)

**Alarm:** `dev-cloudforge-service-degraded` (composite)
**Fires when:** `alb-unhealthy-hosts` AND `alb-5xx` are **both** in `ALARM` state at the
same time.
**Severity:** Page now — by construction, this is the one alarm meant to represent "this
is a real incident," not a single contributing symptom.

---

## What it means

This alarm exists specifically to reduce alert fatigue. Either symptom alone can be
noise — a single target cycling during a routine deploy trips `alb-unhealthy-hosts`
briefly; a short burst of 5xx from a client retry storm trips `alb-5xx` briefly. Neither
alone reliably means "users are actually broken right now." Both firing simultaneously is
a much stronger signal: targets are failing *and* clients are getting errors, at the same
time.

**This is the one alarm to treat as the primary page.** The two underlying alarms will
also fire and email independently — that's expected and useful for the detailed runbooks
below, but this composite is the "drop what you're doing" signal.

## Likely causes

Anything that causes both underlying alarms at once — see `alb-unhealthy-hosts.md` and
`alb-5xx.md` individually. In practice this usually means either:

- A shared dependency (RDS or Redis) failing or badly saturated, causing instances to
  both fail health checks *and* return 5xx to real requests from the same root cause.
- A bad deploy that broke the app broadly enough to affect both health checks and normal
  request handling.
- An AZ-level impairment taking out enough capacity that the survivors are both
  unhealthy under load and erroring under the resulting pressure.

## Diagnose

Work both underlying runbooks in parallel, since they're firing together for a reason:

1. `alb-unhealthy-hosts.md` — confirm which instances/AZ are affected and why.
2. `alb-5xx.md` — confirm what the actual error responses look like (Logs Insights
   query for `status >= 500`).
3. Check `rds-*` and `redis-*` alarms for the same window — a shared dependency failure
   is the most common way to trip both ALB alarms simultaneously.

## Mitigate

Follow whichever underlying cause the diagnosis points to — this composite alarm doesn't
have its own separate fix, it's a signal that says "stop treating this as noise and
actually work the problem." See the individual `alb-unhealthy-hosts.md`, `alb-5xx.md`,
and relevant `rds-*`/`redis-*` runbooks for concrete remediation steps.

## Escalate

This already *is* the escalation point — if this alarm is firing, treat it as a live
incident from the start rather than waiting to see if it clears on its own.

## Verify resolved

Both underlying alarms (`alb-unhealthy-hosts`, `alb-5xx`) return to `OK`; the composite
alarm follows automatically once both legs clear. Recovery email arrives automatically.

## Related

`alb-unhealthy-hosts.md`, `alb-5xx.md` — the two alarms this composite combines. See
`docs/observability/slo.md` for how sustained incidents here consume the Availability and
Correctness error budgets.
