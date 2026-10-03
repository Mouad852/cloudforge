# Experiments (Game Days)

One file per experiment, written in M12 (`PLAN.md` §9). Every number in `PLAN.md` §10's
measurements table must trace back to a file here, to a disaster-recovery drill in
`../disaster-recovery/`, or to a real incident in `../incidents/`.

No experiment has been run yet. Do not pre-fill results: an unmeasured field left honestly
blank is worth more than a plausible invented one.

## Planned experiments

Five high-value experiments, chosen for what the as-built system can actually demonstrate.
Faults are injected with scripted AWS CLI commands, because AWS FIS is not available on this
account's plan (ADR-019, M12).

| # | File | Experiment |
|---|---|---|
| E1 | `01-instance-failure.md` | Instance failure, at prod's real size (1 instance) and with 2 |
| E2 | `02-cache-failure.md` | Redis reboot under load: does the app fail open to Postgres? |
| E3 | `03-load-and-scaling.md` | Load ramp: saturation point, CPU target tracking 1 → 2 |
| E4 | `04-rolling-deploy.md` | Rolling deploy under load, with the 2026-09-25 198 → 0 fix as the "before" |
| E5 | `05-database-restore.md` | Point-in-time restore drill (shared with M11) |
| E6 | `06-full-rebuild.md` | `prod-down` → `prod-up` from snapshot (shared with M11) |
| E7 | `07-bluegreen-deploy.md` | Optional: blue/green cutover and rollback under load |

Not planned, and why: AZ impairment and RDS Multi-AZ failover (RDS is Single-AZ and prod runs
one instance, so there is nothing to fail over to), CPU stress via FIS (unavailable, and the
load test covers scaling), region loss as a game day (a cross-region restore is an optional
M11 task instead).

**Already happened for real:** the 2026-09-30 database password rotation outage. Its
post-incident review, `../incidents/2026-09-30-db-password-rotation.md`, is stronger evidence
than a re-enactment, so it is not recreated here.

## Template

Copy `000-template.md` for every experiment. The field that matters most is **what I changed as
a result**.

```markdown
# Experiment NN — <name>

**Date:** <UTC>                    **Environment:** prod (session start/stop: <UTC> / <UTC>)

## Hypothesis
What you expect to happen, and why, written BEFORE running it.

## Method
Exact fault command, and the k6 load running during it.

## Timeline (UTC)
| Time | Event |
|---|---|
| | Fault introduced |
| | Detection (which alarm or signal, and did the expected one fire?) |
| | Recovery action started |
| | Service restored |

## Measurements
- Detection time:
- Recovery time:
- k6: total requests / failed / error rate:
- Error budget consumed (against `docs/observability/slo.md`):
- Steady state confirmed:

## What surprised me

## What I changed as a result

## Evidence
One CloudWatch graph spanning the incident window, and the k6 summary as text.
```
