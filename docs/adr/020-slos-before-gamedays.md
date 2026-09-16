# ADR-020: SLOs defined before game days, not after

**Status:** accepted   **Date:** 2026-09-16   **Milestone:** M7

## Context

M12 will run game days — deliberately breaking things (EC2 termination, AZ impairment, RDS failover, Redis node loss, CPU saturation) to measure detection and recovery. Each of those experiments needs a way to say how bad the damage was, not just that it happened. Without a target defined in advance, "how bad" collapses into a post-hoc guess: after the fact, any recovery time can be rationalized as "fine," because there was never a line it was measured against.

The alternative — defining acceptable availability/latency/error rates only when writing up M12's results — was rejected before it started: numbers chosen after seeing the outcome aren't a standard, they're a description of what already happened. They can't demonstrate prioritization, because there was nothing to prioritize against.

## Decision

SLIs, SLOs and the error-budget policy are defined now, in M7, in `docs/observability/slo.md`, using real infrastructure that's already collecting data (the Synthetics canary and ALB metrics from the M7 observability module) — not invented in the abstract:

- **SLIs** measured from outside the app (canary success rate, ALB `TargetResponseTime`, ALB non-5xx rate) — an SLI measured by the app's own view of itself can't see the failures that keep the app from reporting at all.
- **SLOs**: 99.5% availability, 99% of requests under 500ms (p99), 99.9% non-5xx, each a 30-day rolling window.
- **Error-budget policy**: >50% budget remaining ships freely; <50% blocks new experiments until the cause is understood; exhausted budget means a deploy freeze until the window rolls.

These are a starting proposal, not a permanent contract — see Consequences.

## Alternatives considered

- **Define SLOs during M12, once game-day data exists** — rejected: see Context. A target set after the measurement isn't a target.
- **Skip formal SLOs, just watch the dashboards** — rejected: dashboards show current state, not whether that state is *acceptable*. Without a numeric target and an error-budget policy, there's no defined threshold for when to stop shipping and start fixing.
- **Industry-default 99.9% (or higher) across the board** — rejected: this is a single-instance-per-AZ, no-multi-region dev/portfolio environment, not a funded SLA product. Copying a blanket "three nines" target would be a number nobody could actually defend if asked why.

## Consequences

- `docs/observability/slo.md` exists before M12 starts, so every game-day experiment measures itself against a real, pre-committed number instead of an after-the-fact judgment call.
- The numbers in that document are explicitly marked as a starting proposal (PLAN.md §10) — once M12 produces real baseline data, targets get adjusted, and the reason for adjusting gets documented rather than silently changing the number.
- Reporting game-day results can now say things like "this experiment consumed 31% of the monthly availability budget," which is a data-grounded prioritization statement, not just "this took N minutes."
