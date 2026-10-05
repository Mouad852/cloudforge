# ADR-019: Scripted AWS CLI fault injection over AWS FIS

**Status:** accepted   **Date:** 2026-10-05   **Milestone:** M12

## Context

CloudForge needs a small, repeatable set of resilience experiments: instance loss, Redis restart,
load-driven scaling, rolling deployment, database recovery, and a full rebuild. AWS Fault Injection
Service is not available on this account's Free plan (`SubscriptionRequiredException`, checked
2026-10-03). Replacing the experiments with console clicks would make the fault, start time, and
cleanup hard to reproduce or audit.

The experiments must be safe enough for a credit-bounded portfolio workload. They run only during
a planned prod session, with bounded load, a stated expected failure mode, UTC logs outside the
repository, and a report that distinguishes measurements from targets.

## Decision

Use explicit AWS CLI fault commands wrapped in repository scripts or documented command sequences:

- E1 terminates a named ASG instance with `--no-should-decrement-desired-capacity`, allowing the
  ASG to replace it.
- E2 reboots the single Redis cache node through ElastiCache's control plane.
- E3 opens the narrow, temporary WAF benchmark exemption through
  `scripts/waf-benchmark-window.sh`; its exit trap removes and verifies the exemption.
- E4 uses the normal `scripts/deploy.sh` rolling-deploy path under k6 load.
- E5 and E6 use the M11 restore and rebuild workflows rather than a second fault mechanism.

Every fault is run with a pre-written experiment report, existing CloudWatch alarms and a defined
cleanup/recovery path. A real incident is evidence, not an experiment to recreate.

## Alternatives considered

- **AWS FIS** — unavailable on the account plan, so it cannot be the project mechanism.
- **Console-only operations** — rejected. They obscure the exact API call, timing and cleanup and
  are difficult for another engineer to repeat.
- **Building dedicated chaos infrastructure** — rejected. Extra Lambdas, templates, or a second
  stack would spend credit and add complexity solely to host a small number of experiments.
- **No intentional faults** — rejected. The project would claim recovery behaviour without
  measuring the most important single-instance and cache failure modes.

## Consequences

The repository documents exactly what is deliberately broken, by which command, and how it is
expected to recover. The scripts and reports do not make a fault safe in every context: they still
require a human confirmation, a live session, and review of the resulting CloudWatch and k6 data.
Results remain pending until each experiment is actually run.
