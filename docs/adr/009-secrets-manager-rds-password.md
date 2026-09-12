# ADR-009: AWS-managed master password via Secrets Manager, not a Terraform-set one

**Status:** accepted   **Date:** 2026-09-11   **Milestone:** M5

## Context

`aws_db_instance` needs a master password. The direct way is a Terraform variable holding the password, either typed in or generated with `random_password` — but that puts the actual database credential inside Terraform state, in plaintext, on every apply from then on. Anyone with read access to state (or to the state backend) has the password, and rotating it means a Terraform apply, not a security operation.

## Decision

Set `manage_master_user_password = true` on the instance instead of `password`. AWS then creates and owns the secret itself in Secrets Manager (named `rds!db-<generated-id>`, never chosen by me), and Terraform never sees the actual password value at all — only the secret's ARN, which I already output from the module (`master_user_secret_arn`).

## Alternatives considered

- **`random_password` resource + `password` argument** — rejected: the password ends up in Terraform state regardless of how it was generated, which is exactly the exposure this decision avoids.
- **Manually create the secret in Secrets Manager, reference its ARN** — rejected as unnecessary manual setup outside Terraform for something AWS already does natively and for free as part of RDS itself.

## Consequences

- The app's IAM policy needs read access to a Secrets Manager ARN that doesn't exist until the RDS instance is actually created — the `compute` module's IAM policy already anticipates this, scoped to the `rds!*` naming pattern AWS always uses for these secrets, added back in M3 ahead of this milestone.
- Nobody, including me, retypes or stores this password anywhere — reading it (e.g. to open a `psql` session for verification) is a deliberate, logged `secretsmanager:GetSecretValue` call, not something sitting in a `.tfvars` file or shell history.
- Rotation becomes an AWS Secrets Manager operation, not a Terraform apply — out of scope for this milestone, but the door is open for automatic rotation later without touching this resource's configuration at all.

## Known issue: SSM-reachable didn't mean actually reachable — a missing egress rule

Proving the "psql from an instance via SSM works" half of this milestone's DoD surfaced a real network bug, unrelated to the password decision above but found while verifying it. The RDS security group's ingress was correctly scoped to the app security group only, and DNS (`db.cloudforge.internal`, ADR-013) resolved fine — but a `psql`/raw-TCP connection attempt from an app instance still failed.

Root cause: the app security group's **egress** only ever allowed port 443 outbound (for SSM, CloudWatch, Secrets Manager, S3) — there was no egress rule for 5432 at all. The RDS security group's ingress rule doesn't matter if the app instance's own security group blocks the packet from leaving in the first place; ingress and egress are independent, and I'd only ever built the ingress half of this specific SG chain.

**Fix:** added a second egress rule to the app security group, `5432` scoped to the data-tier subnet CIDRs specifically (not the whole VPC, and not a direct reference to the RDS security group — the latter would create a circular dependency between the `compute` and `database` modules, since `database` already takes the app security group ID as an input). Confirmed with a raw `/dev/tcp` connectivity check from inside an SSM session before and after — `FAILED` then `REACHABLE` with nothing else changed.

The general lesson: a security group chain has two independent halves per hop (this side's egress, the other side's ingress), and getting only one half right produces a failure that looks like it must be about DNS or routing, when it's actually the simpler half nobody checked.
