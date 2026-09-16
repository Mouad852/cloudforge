# Runbook — ALB elevated 5xx rate

**Alarm:** `dev-cloudforge-alb-5xx`
**Fires when:** more than 10 `HTTPCode_Target_5XX_Count` in a 5-minute window.
**Severity:** Page now — this is one leg of the `service-degraded` composite alarm.

---

## What it means

Targets behind the ALB are returning HTTP 5xx to real clients. Unlike
`alb-unhealthy-hosts`, this doesn't necessarily mean a host is down — a perfectly
"healthy" instance (per its `/readyz` check) can still be returning 500s on specific
request paths, since the health check only proves the shallow dependency checks pass,
not that every endpoint works.

## Likely causes

- An unhandled panic or error path in the app on a specific route (check the
  `CloudForge/App` → `ExceptionCount` metric, sourced from the `status >= 500` log
  filter, to confirm this is app-side and not the ALB's own 5xx generation).
- A downstream dependency (RDS, Redis) is reachable but erroring under load — the app
  passes its shallow `/readyz` check yet fails specific queries.
- A bad deploy — correlate the timestamp against the most recent instance refresh.

## Diagnose

1. **CloudWatch → Logs → `/cloudforge/dev/app` → Logs Insights** — query for
   `fields @timestamp, msg, status, error | filter status >= 500 | sort @timestamp desc`
   to see the actual error messages, not just the count.
2. Check whether 5xx responses are concentrated on one route or spread across all of
   them — a single bad endpoint points at app logic; everything failing points at a
   shared dependency.
3. Cross-check `rds-cpu` / `rds-connections` / `redis-memory` alarms for the same time
   window — a saturated dependency often shows up as 5xx before it shows up as an
   explicit alarm of its own.

## Mitigate

- If it's a bad deploy: roll back — redeploy the previous known-good S3 artifact key and
  trigger a new instance refresh (see `docs/runbooks/` once M8's CI/CD rollback path
  exists; until then, this is a manual launch-template revision + instance refresh).
- If it's a saturated dependency: address that dependency directly (see the relevant
  `rds-*` / `redis-*` runbook) — the 5xx alarm will clear once the root cause does.
- If it's an isolated, low-frequency route bug: this can usually wait for a normal fix
  cycle rather than an emergency rollback — use judgment based on request volume on that
  route.

## Escalate

If the 5xx rate keeps climbing after ruling out a bad deploy and a saturated dependency,
treat it as an unknown regression and roll back to the last known-good state rather than
continuing to debug live.

## Verify resolved

`HTTPCode_Target_5XX_Count` drops back under 10 per 5-minute window; recovery email
arrives automatically via the alarm's `ok_actions`.

## Related

Half of the `service-degraded` composite alarm (paired with `alb-unhealthy-hosts`). Also
the direct input to the Correctness SLI in `docs/observability/slo.md`.
