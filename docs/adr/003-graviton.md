# ADR-003: ARM/Graviton (`t4g`) for EC2

**Status:** accepted   **Date:** 2026-09-09   **Milestone:** M3

## Context

The compute layer needs an instance family for the ASG's launch template. AWS's Graviton
(ARM) instances are consistently ~20% cheaper than the equivalent x86 (`t3`) family at
equal performance, which matters on a project run against a fixed personal credit balance
(`PLAN.md` §4). The usual objection to ARM — "our software doesn't support it" — doesn't
apply here: the app is a Go binary, and Go cross-compiles to `arm64` with one environment
variable (`GOARCH=arm64`, already exercised in M2's `make build` target), so there is no
toolchain cost to paying for.

## Decision

The launch template (`terraform/modules/compute`) uses the AL2023 **arm64** AMI and defaults
to `t4g.micro`. RDS (M5) will make the same call for the same reason when it's built.

In practice, `eu-west-3a`/`eu-west-3b` had no spare `t4g.micro` capacity when this was first
applied, so `environments/dev` currently pins `instance_type = "t4g.small"` instead (still
Graviton, still cheap for a dev environment that's mostly stopped) — a deliberate standing
choice now, not a workaround waiting to be reverted. See the compute module's own comment on
that variable for the specifics.

## Alternatives considered

- **x86 (`t3`)** — the safe default with zero cross-compilation to think about, but pays a
  real cost premium for no benefit here, since the one thing that would justify it (a
  toolchain/runtime that only ships x86 binaries) doesn't exist in this stack.

## Consequences

- Every artifact that lands on these instances (the Go binary, in particular) must be built
  for `arm64` — already true since M2, so this ADR changes nothing about the app, only
  confirms the compute layer matches what the app was already built for.
- Graviton capacity in a given AZ is not guaranteed at any given moment — this was a real,
  live constraint during M3's build (`t4g.micro` and briefly `t4g.small` both hit
  `InsufficientInstanceCapacity` in this account/region at different points), not a
  hypothetical. Worth remembering if a future instance-refresh or scale-out event stalls:
  check for a capacity error before assuming the config is wrong.
