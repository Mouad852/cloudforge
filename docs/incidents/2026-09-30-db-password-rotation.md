# Prod API down after a database password rotation - 2026-09-30

**Severity:** SEV1   **Duration:** 2026-09-30 00:31 to 2026-10-01 16:26 UTC (about 40 hours)
**Impact:** every prod request that touched the database failed with a 500: listing, reading,
creating and deleting products, and image upload and download. `/healthz` kept answering 200,
so the ALB kept the instance in service. The month's error budget (99.5% availability, about
3.6 hours, `docs/observability/slo.md`) was spent about eleven times over.

Found by accident, during a deploy, not by an alarm meant for it.

## Timeline (UTC)

- **09-30 00:08:58** - Secrets Manager rotates the RDS master password, as it does every 7 days
  for an RDS-managed secret.
- **00:26** - Last successful canary run. The pool's connections were opened before the
  rotation and stay logged in.
- **00:31** - First 500. As the pool replaces its connections (each lives up to an hour), every
  new one logs in with the password the app read at boot, and Postgres refuses it.
- **00:31 to 10-01 16:21** - Every canary run, one every 5 minutes, fails. No alarm fires.
- **10-01 ~16:05** - Deploy of the M10 timeout fixes starts (`scripts/deploy.sh prod`).
- **16:18** - k6's smoke load polls `/readyz` on the old instance, which answers 503 (Postgres
  unreachable for it) 596 times.
- **16:21** - `prod-cloudforge-alb-5xx` fires on the k6 errors: the first alert of the incident.
- **16:18 to 16:26** - The instance refresh replaces the old instance. The new one reads the
  current password at boot. First passing canary run: **16:26**.
- **16:23 to 16:50** - Investigation: app logs (500s only, no cause), the canary history, the
  secret's `LastRotatedDate`, ALB access logs.
- **16:57** - Fix deployed (commit 6046480), then a rotation forced by hand to prove it.

## What happened, and why

1. **The app read the database password once, at boot** (`loadConfig`), and built every
   connection from that copy. That was safe only as long as the password never changed.
2. **The password did change.** `manage_master_user_password` (ADR-009) creates a secret that
   Secrets Manager rotates every 7 days by default. ADR-009 describes rotation as something to
   enable later; it was in fact on from the start, and nothing in the repository said so.
3. **Prod had not lived through a rotation before.** It only started serving on 2026-09-25,
   after the S3 boot-loop fix. Dev never did: it is destroyed every night and rebuilt with a new
   database and a new secret.
4. **Nothing alerted, for two reasons.** The canary's result only fed a dashboard graph; no
   alarm watched it. And the 5xx alarm needs more than 10 errors in 5 minutes: with no real
   traffic, the canary's one request per 5 minutes never reached it. Every prod alarm watched the
   infrastructure (CPU, connections, unhealthy hosts), and all of it was healthy.
5. **The logs did not say why.** `writeError` sent the error to the client and logged nothing,
   so the app's log showed 500s with no cause. The cause had to be inferred from timing.

## What went well

- The deploy runbook's k6 gate made the broken instance visible: it was the only traffic large
  enough to cross the 5xx threshold.
- The alarm email arrived, the day after the SNS encryption fix (G12) made alarm delivery work
  at all. A day earlier it would have failed silently too.
- The evidence existed and agreed: the canary's run history, the app's per-request log lines,
  the secret's rotation date and the ALB access logs.

## What went badly, or was lucky

- 40 hours of a total outage, found by luck. Without the deploy, the API would have stayed down
  until the next deploy, or until someone looked at the dashboard.
- Health checks were green throughout. `/healthz` is shallow on purpose (ADR-006), so the
  ALB never stopped sending traffic to an instance that could not reach its database.
- The next rotation was due by 2026-10-07, and the instance deployed during the incident would
  have broken the same way.

## Changes made because of this

- [x] New database connections log in with the current password from Secrets Manager
  (`BeforeConnect` hook in `app/store.go`), with a test that rotates a fake secret. Commit
  6046480, deployed to prod 2026-10-01.
- [x] Every 5xx logs the error behind it (`withRequestLogging`). Same commit.
- [x] Proven against a real rotation: forced by hand on 2026-10-01, see Verification below.
- [ ] `<env>-cloudforge-canary-failed` alarm on the canary's `SuccessPercent`, and its runbook
  `docs/runbooks/canary-failed.md`.
- [x] ADR-009 corrected: rotation is on, every 7 days, and the app depends on reading the
  secret for each new connection.

## Verification

The fix was deployed at about 16:50 on 2026-10-01 (commit 6046480, k6 gate: 0 failed requests
out of 2,215). A rotation was then forced by hand
(`aws secretsmanager rotate-secret`) and completed at **16:59:09**. Checked at 12:09 on
2026-10-02, 19 hours later:

- The same instance (`i-0bdebf097b97c29f5`) served throughout, so it never re-read the
  password at boot. Every connection in its pool was replaced many times over (connections
  live up to an hour).
- `/api/products`: 230 requests, all 200. On 2026-09-30 the first 500 came 22 minutes after
  the rotation.
- No `password`, `authentication` or `SASL` error in the app's log.
- The last 100 canary runs all passed.
