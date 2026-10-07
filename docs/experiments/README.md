# Experiments (Game Days)

Every result in this directory traces to a recorded experiment, a
[disaster-recovery drill](../disaster-recovery/), or a real [incident](../incidents/).

The six completed reports contain measured results. The evidence deliberately distinguishes
measurements from assumptions and estimates.

## Measured experiments

Faults were injected with scripted AWS CLI commands because AWS FIS is not available on this
account's plan (ADR-019).

| # | File | Experiment |
|---|---|---|
| E1 | `01-instance-failure.md` | Instance failure, at prod's real size (1 instance) and with 2 |
| E2 | `02-cache-failure.md` | Redis reboot under load: does the app fail open to Postgres? |
| E3 | `03-load-and-scaling.md` | Load ramp: saturation point, CPU target tracking 1 → 2 |
| E4 | `04-rolling-deploy.md` | Rolling deploy under load, with the 2026-09-25 198 → 0 fix as the "before" |
| E5 | `05-database-restore.md` | Point-in-time restore drill (shared with M11) |
| E6 | `06-full-rebuild.md` | `prod-down` → `prod-up` from snapshot (shared with M11) |
The repository does not claim a measured blue/green cutover, AZ impairment, Multi-AZ failover,
or cross-region recovery exercise. The existing reports document the scope and limits of the
evidence that was collected.

**Already happened for real:** the 2026-09-30 database password rotation outage. Its
post-incident review, `../incidents/2026-09-30-db-password-rotation.md`, is stronger evidence
than a re-enactment, so it is not recreated here.
