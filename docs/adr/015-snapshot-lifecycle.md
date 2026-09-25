# ADR-015: Snapshot-based recovery for the dev database

**Status:** accepted   **Date:** 2026-09-12   **Milestone:** M5

## Context

`dev` is designed to be disposable end-to-end (ADR-012) — I expect to tear the whole environment down and rebuild it repeatedly. Without a real backup/restore story, "tear down the database" and "lose the database's data permanently" would be the same action. That's fine for a database with nothing in it, but it's not a pattern I want to demonstrate as acceptable, since the same module ships to `prod` eventually.

## Decision

Two pieces work together:

- The `aws_db_instance` resource already sets `skip_final_snapshot = false`, so AWS is forced to take a snapshot the moment before it deletes the instance, regardless of how the destroy is triggered.
- A new `snapshot_identifier` variable (default `null`) on the module: when set, RDS creates the new instance from that snapshot's data instead of an empty database.
- `make dev-down` / `make dev-up` at the repo root tie the two together: `dev-down` runs `terraform destroy` (triggering the automatic final snapshot as a side effect); `dev-up` looks up the most recent manual snapshot via the AWS CLI and, if one exists, passes it straight into `terraform apply -var="snapshot_identifier=..."` — no snapshot ID to hunt down by hand.

## Alternatives considered

- **Automated backups only (`backup_retention_period`), no snapshot-on-destroy** — rejected. Automated backups protect against data loss *while the instance exists*; they don't help once the instance itself is deleted, which is exactly the case this ADR is about.
- **Manually snapshot before every `terraform destroy`** — rejected as a discipline problem waiting to happen: it only works if I remember to do it every single time, with no enforcement. `skip_final_snapshot = false` makes it structurally impossible to forget.
- **Leave `dev` genuinely disposable, no restore path** — rejected once I actually thought through what "torn down for a demo, rebuilt later" really implies: the whole point of the ADR-012 ephemeral pattern is to save cost while idle, not to throw away real work in progress.

## Verified with a real round trip

Tested end-to-end, not just planned: inserted a marker row (`round_trip_marker`, one row with a timestamped note), then ran the actual destructive test.

`make dev-down` destroyed the entire `dev` environment (not just the database — `terraform destroy` at the root module tears down everything, which is expected and fine given ADR-012). The database instance `db-564JTKEIXYXYSK24M46OSVFHQA` was deleted, taking final snapshot `dev-cloudforge-db-final-74308b3e` as part of that operation — confirmed independently via `aws rds describe-db-snapshots` afterward, status `available`.

`make dev-up` found that snapshot automatically and restored from it, producing a **new** instance (`db-36IT54HTLPY26A4DSNY2DQLX2M`) with a **new** AWS-managed master-password secret (`manage_master_user_password` correctly re-issued a fresh Secrets Manager secret rather than trying to reuse the old one, which no longer existed). Querying the restored instance for the marker row returned exactly the one row inserted before the destroy — proof the mechanism actually preserves data, not just that a database exists afterward.

## Known issues found during the round trip (unrelated to the snapshot mechanism itself, but blocking the test)

- **Two S3 buckets (`artifacts`, `alb-logs`) don't allow `terraform destroy` to fully complete.** Both are versioned and contain real objects; without `force_destroy = true`, AWS refuses `DeleteBucket` with `BucketNotEmpty`. This didn't affect the database/snapshot mechanism itself — the RDS instance still deleted and snapshotted correctly — but it meant `dev-down` never cleanly finished on its own, twice, and had to be re-run before the environment was actually fully torn down. **Not yet fixed** — worth adding `force_destroy = true` to these dev-only buckets so `dev-down` completes in one pass.
- **A stuck Terraform state lock** after the first `dev-down`, caused by a transient local DNS/network blip while Terraform was mid-poll (confirmed via `nslookup` and AWS's own side showing the delete had actually already succeeded) — resolved with `terraform force-unlock` once confirmed no other process could be holding it.
- **The recreated app instances came up with no working SSM agent at all** — a third instance of the exact AL2023 "minimal AMI variant" bug ADR-008 already documents twice for the NAT instance, this time hitting `compute`'s own AMI filter instead. See ADR-005 for that specific fix.

> **2026-09-25:** CI now does what `make dev-up` does. `apply (dev)` passes the newest
> `dev-cloudforge-db` manual snapshot on every apply, and `snapshot_identifier` is in
> `ignore_changes`, so a snapshot is only ever used when the instance is being created. Without
> that, any apply with a newer snapshot ID would have replaced the running database. See ADR-026.
> The bucket issue above was fixed on 2026-09-13 (`a32b754`): the dev `artifacts` and ALB-logs
> buckets set `force_destroy`, as the `images` bucket has since it was added the same day.
