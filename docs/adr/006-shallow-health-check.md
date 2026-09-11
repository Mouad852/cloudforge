# ADR-006: Shallow health check for the ALB, deep check kept separate

**Status:** accepted   **Date:** 2026-09-11   **Milestone:** M4

## Context

The app exposes two health endpoints: `/healthz`, which just returns `200 ok` if the process can answer HTTP at all, and `/readyz`, which actually pings Postgres and Redis and reports their status. I had to decide which one the ALB's target group health check should call.

## Decision

Both target groups (`blue` and `green`) point their health check at `/healthz`, not `/readyz`. `/readyz` still exists and is monitored, but the ALB never calls it.

## Alternatives considered

- **Point the ALB at `/readyz`** — looks like the more thorough choice, but every app instance shares the same Postgres and Redis. If either dependency has even a brief blip, every instance would fail the deep check at the same moment, and the ALB would mark the entire target group unhealthy simultaneously instead of just one instance. That turns a single dependency hiccup into a full outage of my own making, on top of whatever the dependency issue already caused.
- **Point the ALB at `/readyz`, but tune around the failure mode (e.g. very high unhealthy threshold)** — rejected as treating a design problem with a knob; it would just delay the same fleet-wide flap rather than prevent it.

## Consequences

- The ALB's view of "healthy" is narrow: it only proves the process is alive and serving HTTP, not that the app can actually complete a database-backed request. A real Postgres outage would leave every instance individually "healthy" per the ALB while requests that touch the database fail.
- That gap is deliberate and bounded by scope — `/readyz` exists specifically to carry the deeper signal, just routed to monitoring instead of to traffic routing. A production system at a larger scale would pair this with an alarm on `/readyz` (or a synthetic canary) so a real dependency outage still pages someone, even though it no longer takes the fleet out of ALB rotation.
- This is the same principle Redis failure handling inside `/readyz` already follows at the code level: a dead cache degrades the response, it doesn't flip the instance to unhealthy, because the app fails open to Postgres for reads.
