# ADR-004: App artifact is a static Go binary in S3, pulled by cloud-init

**Status:** accepted   **Date:** 2026-09-09   **Milestone:** M3

## Context

Instances need to run the CloudStore API (M2) somehow. `CGO_ENABLED=0` already produces a
single static ~15MB binary with no runtime dependency (no JVM, no Python, no shared libs to
match) — the only question is how that binary gets from a build machine onto a running
instance.

## Decision

The binary is uploaded to the `artifacts` S3 bucket (`terraform/modules/storage`) at a fixed
key (`cloudstore-api/cloudstore-api`), and the launch template's user-data pulls it down with
`aws s3 cp` using the instance's own IAM role (`s3:GetObject`, scoped to that one bucket —
`docs/security/README.md`) — no credentials baked into the AMI or the template. `systemd`
then owns the running process (`Restart=always`, `TimeoutStopSec=40` — longer than the app's
own 35s graceful-drain window, ADR-004's own drain logic from M2, so systemd never SIGKILLs
mid-drain).

Today, that upload is a manual step (`aws s3 cp` by hand, done for M3's own evidence). M8
automates it: a CI pipeline builds, uploads, and triggers an instance refresh. Nothing about
this ADR changes when that lands — it's the same artifact, same pull mechanism, just
triggered by a pipeline instead of a person.

## Alternatives considered

- **Golden AMI** — bake the binary into a custom AMI per release. Correct at scale, but a
  slow iteration loop for a project explicitly timeboxed against overbuilding the app itself
  (M2's own framing: "nobody is hiring you for this API"). Rebuilding an AMI for every change
  during active development would cost more time than it saves.
- **Docker on EC2** — would need a container runtime installed and managed on every instance,
  and starts pulling the whole architecture toward "just use ECS/EKS," which isn't this
  project's story (`PLAN.md`'s stack is EC2 + ASG, not a container orchestrator).

## Consequences

- An instance refresh or replacement always pulls whatever is at that one S3 key right now —
  there's no per-version pinning yet. Fine for a single dev environment; will need a real
  answer (versioned keys, or the bucket's own object versioning already enabled in
  `modules/storage`) once blue/green (M8) needs two different versions live at once.
- The binary must exist at that key *before* any instance boots, including the very first
  ones an ASG launches — learned the hard way during M3: applying the compute module before
  uploading the binary means the first boot's `aws s3 cp` fails, `set -euo pipefail` aborts
  the rest of user-data, and the instance comes up with no app running and no obvious symptom
  beyond "nothing answers on port 8080."
- The same gap resurfaced during M6, in a more misleading form: editing `app/cache.go` and
  `app/config.go` for the Redis TLS fix and rerunning `terraform apply` changes nothing at
  runtime by itself — the S3 key still holds the pre-fix binary until a manual `make build` +
  `aws s3 cp` happens, followed by an instance refresh onto the new launch template version.
  Running instances kept the old code while every other signal (launch template version,
  environment variables, Terraform state) looked correct, which turned a one-line Go fix into
  a long `/readyz`-timeout debugging detour that looked like a Redis configuration problem.
  Automating this gap away is exactly what M8's `app.yml` pipeline exists to do.
