# ADR-001: Terraform state in S3 with native locking

**Status:** accepted   **Date:** 2026-09-05   **Milestone:** M0

## Context

Terraform needs somewhere durable to store state, and something to prevent two concurrent `apply` runs from corrupting it. The traditional pattern pairs an S3 bucket (state storage) with a DynamoDB table (locking). Terraform 1.11 removed the need for the DynamoDB half by adding native S3 locking via a `.tflock` object in the same bucket.

This project runs on Terraform 1.15.6, well past that threshold.

## Decision

Use a single S3 bucket (`terraform/bootstrap/`) for state, with `use_lockfile = true` in each environment's `backend "s3"` block for locking. No DynamoDB table.

## Alternatives considered

- **S3 + DynamoDB lock table** — the long-standing standard pattern, still what most existing tutorials and older repos show. Rejected: one more resource to provision, tag, secure and pay for (trivial cost, but non-zero operational surface) when the backend itself now does the same job.
- **Terraform Cloud / HCP Terraform remote backend** — manages state and locking with zero infrastructure of your own. Rejected for this project specifically: the goal is to demonstrate hands-on understanding of the underlying mechanics (state storage, locking, encryption), and a managed backend would hide exactly what this project exists to show.

## Consequences

- One fewer resource type to explain, secure, and pay for than the DynamoDB-table pattern.
- Requires Terraform ≥ 1.11 in every environment and in CI — pinned in `versions.tf`'s `required_version`, so an older Terraform binary fails fast with a clear version error rather than a confusing lock-related one.
- The state bucket itself (`terraform/bootstrap/`) is provisioned once, applied with **local** state (there's no bucket yet to hold its own state), and never re-applied — a deliberate, documented exception to "everything is Terraform," not an oversight.
