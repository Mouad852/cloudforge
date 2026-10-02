# Runbook — API canary failing

**Alarm:** `<env>-cloudforge-canary-failed`
**Fires when:** the Synthetics canary `<env>-api-avail` has a failed run in 2 consecutive
5-minute windows (`SuccessPercent` < 100).
**Severity:** Page now — the canary calls `GET /api/products` through the ALB, the way a
customer does, so a failure here is very likely a customer-facing error.

---

## What it means

The canary is the only check that exercises the API end to end: ALB, app, Redis and Postgres.
Every other alarm watches one piece of infrastructure, and all of them can stay green while
the API fails. That is exactly what happened on 2026-09-30: the app could not log in to
Postgres for 40 hours, every canary run failed, and no alarm fired, because this one did not
exist yet (`docs/incidents/2026-09-30-db-password-rotation.md`).

`/healthz` does not touch the database (ADR-006), so the ALB keeps sending traffic to an
instance in this state. Do not expect `alb-unhealthy-hosts` to fire alongside this one.

## Likely causes

- The app cannot reach or log in to Postgres: a rotated password the app did not pick up, a
  security group change, or RDS restarting or failing over.
- A bad deploy: correlate with the last instance refresh.
- The ALB or WAF is rejecting the canary: a WAF rule change, or the canary's IP hitting the
  rate limit.
- The canary itself is broken (a runtime deprecation, or its IAM role). The API is then fine,
  and the canary needs fixing instead.

## Diagnose

1. **What does the API return right now?**
   `curl.exe -s -w " %{http_code}\n" http://<alb-dns>/api/products` and `/readyz`. `/readyz`
   reports Postgres and Redis separately.
2. **Why are requests failing?** CloudWatch → Logs → `/cloudforge/<env>/app` → Logs Insights:
   `fields @timestamp, path, status, error | filter status >= 500 | sort @timestamp desc`.
   The `error` field carries the cause (added after the 2026-09-30 incident).
3. **When did it start?** CloudWatch → Synthetics → `<env>-api-avail` → the run history shows
   the first failed run. Compare it with the last deploy, the secret's `LastRotatedDate`
   (`aws secretsmanager describe-secret`), and RDS events.
4. If the API answers 200 to `curl` but the canary still fails, open the failed run's
   screenshot and HAR file (in the artifacts bucket under `canary/<env>/`): the canary itself
   is the problem.

## Mitigate

- **Database login failures** (`password authentication failed` in `error`): replace the
  instance, which reads the secret again on boot:
  `aws autoscaling start-instance-refresh --auto-scaling-group-name <env>-cloudforge-app`.
  Since commit 6046480 this should not happen after a rotation; if it does, the
  `BeforeConnect` hook in `app/store.go` is not working.
- **Bad deploy:** roll back (`docs/runbooks/deployment.md`, "Rolling back").
- **WAF blocking the canary:** check the web ACL's sampled requests for the blocked rule.

## Verify resolved

Two passing canary runs in a row; the alarm returns to `OK` and the recovery email arrives.
