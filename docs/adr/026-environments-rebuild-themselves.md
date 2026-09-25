# ADR-026: A rebuilt environment brings itself back to a working state

**Status:** accepted   **Date:** 2026-09-25   **Milestone:** M10

## Context

`nightly-destroy.yml` tears `dev` down every night at 23:00 UTC (ADR-012), and the next push
to `terraform/**` rebuilds it. That round trip had rarely completed: the only final
snapshots of the `dev` database are from 2026-09-12, 09-17, 09-24 and 09-25, and CI's
`terraform` commands failed for lack of the required `environment` variable until `6c71ca2`
(2026-09-24). Once it did run, the rebuilt `dev` came back broken in three ways:

- **No schema.** Migrations only ran through the docker-compose `migrate` service locally.
  No deployed environment had ever created its tables automatically; `dev` and `prod` both had
  their `products` table created by hand over SSM on 2026-09-24.
- **No app binary.** The artifacts bucket is recreated empty (`force_destroy` on `dev`), and
  only `app.yml`, on a push to `app/**`, ever uploads one. The instances' user data ran
  `aws s3 cp`, got a 403 for the missing object, and stopped. User data never re-runs, so they
  stayed broken.
- **No data.** `make dev-up` restores the newest final snapshot (ADR-015), but the CI apply
  never passed one, so every CI rebuild started from an empty database.

Keeping `dev` up around the clock instead was ruled out on cost: NAT instance, RDS, Redis,
ALB and EC2 running 24/7 would eat into the remaining promotional credit.

## Decision

Make a rebuild converge on its own, with no manual step:

- **The app applies its migrations at startup** (`app/migrate.go`, golang-migrate with the pgx
  v5 driver). The SQL files are embedded in the binary. The driver holds a Postgres advisory
  lock, so two instances booting together take turns. The app retries for about a minute
  before exiting, because systemd (`RestartSec=2`) gives up on a unit after 5 failed starts
  in 10 seconds. `000001_create_products.up.sql` became `CREATE TABLE IF NOT EXISTS` so the
  hand-made tables on `dev` and `prod` are adopted and recorded as version 1, not rejected.
- **The instances wait for the binary** (`user_data.sh.tpl`): they retry the download every
  10 seconds for up to 15 minutes instead of failing on the first 403.
- **`scripts/ensure-artifact.sh`** uploads the binary only when the environment has none (a
  404 from `HeadObject`). It never replaces an existing artifact: shipping a new version stays
  `deploy.sh`'s job, with its instance refresh and k6 gate. Any other error, such as a 403,
  stops it without uploading. `apply (dev)`, `apply (prod)` and `make dev-up` all run it after
  the apply.
- **`apply (dev)` passes the newest `dev-cloudforge-db` manual snapshot** on every apply, the
  same lookup `make dev-up` does.
- **`snapshot_identifier` is in `ignore_changes`** on the RDS instance. Without it, the
  previous point would be destructive: a changed `snapshot_identifier` forces a replacement,
  so the first apply after a new final snapshot existed would have deleted the running
  database and restored it from the snapshot. With it, the value only takes effect when the
  instance is created.
- **`terraform.yml` has a `workflow_dispatch` trigger**, so `dev` can be rebuilt with "Run
  workflow" instead of a throwaway commit. It runs the same approval-gated jobs as a push;
  reject `apply (prod)` when only `dev` needs rebuilding.

## Alternatives considered

- **Run `deploy.sh` from the apply job.** Rejected: right after a from-scratch apply, no
  instance is healthy yet, so the k6 gate fails immediately, and an instance refresh adds
  several minutes to replace instances that only needed a file that wasn't there yet.
- **A separate migration step in CI** (the `migrate` container, or SSM `send-command` against
  an instance). Rejected: the database is only reachable from inside the VPC, so this means
  a runner with network access or an SSM round trip. It would also only cover CI, not an
  instance the ASG replaces on its own.
- **Prune old final snapshots.** Not done: snapshots are billed on data actually stored, not
  on the 20 GB allocated to the instance, so a month of nightly snapshots of this database
  costs cents.

## Consequences

- A failed migration marks the schema version as dirty, and every instance then refuses to
  start until someone fixes the migration and clears the flag with golang-migrate's `force`.
  The database tests in `handlers_test.go` now run the migrations, so a broken one should fail
  `go test` against docker-compose before it reaches an environment.
- A from-scratch rebuild runs the binary built from the commit being applied, not necessarily
  the one `app.yml` last deployed. Both come from `main`, so the rebuild is never older.
- `apply (prod)` does not restore from a snapshot. `prod` is not destroyed nightly, and
  whether a rebuilt `prod` should restore automatically is a disaster-recovery decision for M11.
- Every CI apply after a deploy shows `aws_launch_template.app` "updated in-place": Terraform
  removes the `deploy-<sha>` description `deploy.sh` put on the version. That creates an
  identical new version, and the ASG (on `$Latest`) is not refreshed. It is noise, not drift.

## Found while verifying

Testing this through real deploys exposed two problems with the deploy path itself, fixed the
same day:

- **The k6 deploy gate was blocked by the WAF's per-IP rate limit** (2,000 requests per
  5 minutes, ADR-025). Five virtual users with no pause send about 34 requests a second from
  one runner IP. On 2026-09-25 the WAF blocked 13,335 of them. `load-test.js` now sleeps
  1 second per iteration: about 1,500 requests per 5 minutes.
- **Deploys to a one-instance group had an outage.** `dev` and `prod` both run one instance
  (the defaults CI applies). With only `MinHealthyPercentage = 100`, an instance refresh
  terminated the old instance before launching the new one. The ALB returned 198 errors in
  the gap. `deploy.sh` and the compute module now also set `MaxHealthyPercentage = 200`, so
  the replacement launches first. The next deploy launched at 15:55:42, terminated the old
  instance at 15:58:57, and the ALB returned 0 errors.
- **The first deploy shipped old code.** The binary it uploaded was built from `edb536c`, a
  2026-09-22 commit (`go version -m` on the artifact showed `vcs.revision=edb536c`), while the
  run for the new commit was still waiting for approval. The likely cause is an older
  `deploy (dev)` job that had been waiting for approval since then. GitHub keeps pending
  deployments for 30 days, so only approve the run for the newest commit.

## Verified

- 2026-09-25, locally: on an empty database the migration creates the table, and a second run
  is a no-op. With `products` present but no `schema_migrations` (the state of `dev` and
  `prod`), the app logs `"schema up to date","version":1` and starts.
- 2026-09-25, `dev`: an instance booted with the new binary logged
  `"schema up to date","version":1` against a database that had no `products` table, and
  `GET /api/products` went from `500` to `200 []`.
- 2026-09-25, `dev`: with a real `terraform plan` against `dev`'s state and
  `-var snapshot_identifier=dev-cloudforge-db-final-acc22816`, the database was
  `must be replaced` before the `ignore_changes` change and absent from the plan after it.
- 2026-09-25, `dev`: `ensure-artifact.sh` left the existing artifact alone. The missing
  (`404`) and forbidden (`403`) cases were tested with stand-in `aws`, `terraform` and `make`
  commands.
- 2026-09-25, `dev`, the full round trip with no manual step: a product `survives-the-night`
  was created at 16:48 UTC. `nightly-destroy` (run by hand) deleted `dev` and took final
  snapshot `dev-cloudforge-db-final-62798470` at 17:02. `terraform` (run by hand with "Run
  workflow") restored the database from it at 17:25 and launched an instance at 17:34, before
  any binary existed. `ensure-artifact.sh` uploaded one at 17:35:00, the instance's wait loop
  picked it up, and the app logged `"schema up to date","version":1` at 17:35:11.
  `GET /api/products` then returned `survives-the-night` with its original ID.
