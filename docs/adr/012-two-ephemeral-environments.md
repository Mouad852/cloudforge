# ADR-012: Two environments, both ephemeral

**Status:** accepted   **Date:** 2026-09-06   **Milestone:** M1

## Context

A typical team setup runs three always-on environments — dev, staging, prod — each a full copy of the infrastructure. On a fixed personal credit balance (PLAN.md §4), every environment left running around the clock multiplies the fixed costs (NAT, RDS, ALB, CloudFront) by however many environments exist, regardless of whether anyone is actually using them at that moment.

This project's actual usage pattern is: build, demo, or test against an environment for a session, then not touch it again for days. Paying 24/7 rates for that pattern is the wrong trade — the same one behind ADR-008's NAT choice.

## Decision

Exactly **two** environments — `dev` and `prod` — and both are **ephemeral by design**: brought up when needed, torn down when not, rather than left running. `terraform/environments/dev/` and `terraform/environments/prod/` are separate state files (ADR-002) and separate directories, so bringing one up or down never touches the other.

The tooling that makes teardown-and-restore painless (RDS snapshot-based `dev-down`/`dev-up`, per ADR-015) lands later, once there's an RDS instance to snapshot — this ADR fixes the structural decision (two environments, neither meant to run continuously) now, at the point where the second environment directory (`dev`) first exists.

## Alternatives considered

- **Three always-on environments (dev/staging/prod)** — closer to a typical team setup, but a middle "staging" tier adds a third full set of fixed costs (NAT, compute, database) for a single-person project with no second team to gate a staging step for. Rejected on cost, not on the general merit of staging environments.
- **Everything always-on** — simplest mentally (nothing to remember to tear down), but the direct cause of the credit-forfeiture risk this project is already working around (ADR-021) — a personal-credits budget doesn't forgive infrastructure left running by accident.

## Consequences

- Nothing runs by default; forgetting to `apply` an environment is the safe failure mode, not forgetting to destroy one.
- The Makefile targets referenced in PLAN.md §7 (`dev-up`, `dev-down`, `prod-up`, `prod-down`) are the enforced entry point for this workflow once they exist — direct `terraform apply`/`destroy` inside an environment directory still works today because that tooling isn't built yet.
- Demoing the project means a short "bring it up" wait before it's usable, rather than an always-warm environment — an accepted trade for a portfolio project, not something a real product would choose.
