# ADR-002: Separate state file per environment, not Terraform workspaces

**Status:** accepted   **Date:** 2026-09-05   **Milestone:** M0

## Context

`dev` and `prod` need isolated Terraform state — a broken or destructive `apply` in `dev` must have zero ability to touch `prod`'s state or resources. Terraform offers two common ways to do this: workspaces (one state file, environment selected by `terraform workspace select`), or a separate state file per environment addressed by a distinct backend `key`.

## Decision

One shared state **bucket** (`terraform/bootstrap/`, applied once), but a distinct state **file** per environment via the backend `key` (e.g. `dev/terraform.tfstate`, `prod/terraform.tfstate`) — set up when the environment directories are written in M1. No Terraform workspaces.

## Alternatives considered

- **Terraform workspaces** — a single config, `terraform workspace select prod` switches which state file it reads. Rejected: the environment you're targeting becomes invisible local shell state — nothing in the command you're about to run shows whether you're pointed at `dev` or `prod`. A single distracted `apply` after forgetting to switch workspaces is a well-known way this pattern bites people in production. Separate directories with separate backend configs make the target explicit in the file path itself.
- **Separate S3 buckets per environment** — maximal isolation, but adds a second bucket to provision and secure for a project whose blast-radius concern is state-file corruption, not bucket-level access boundaries between environments run by the same person.

## Consequences

- Running `terraform apply` always happens from inside `environments/dev/` or `environments/prod/` — the directory you're in *is* the safety check.
- One bucket to secure and pay for (already built in `terraform/bootstrap/`, see ADR-001), not two.
- The actual per-environment `backend "s3" { key = ... }` blocks land in M1 alongside the first real environment configs — this ADR describes the shared-bucket design decided now; the isolation itself becomes real code in M1.
