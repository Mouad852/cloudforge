# ADR-013: Private Route 53 hosted zone for internal service names

**Status:** accepted   **Date:** 2026-09-11   **Milestone:** M4

## Context

RDS (M5) and ElastiCache/Redis (M7) will each hand back an AWS-generated endpoint hostname once created. I want the app to reference stable names — `db.cloudforge.internal`, `cache.cloudforge.internal` — instead of wiring the raw generated hostname into app config directly. Creating the zone itself in M4, ahead of the records it will eventually hold, means it's simply there and ready when M5 and M7 land.

## Decision

Create `aws_route53_zone.private`, named `cloudforge.internal`, with a `vpc` block associating it to this environment's VPC. Attaching a `vpc` block is what makes a Route 53 zone private — resolution is scoped to that VPC only, nothing outside it can resolve these names. No records exist in it yet; M5 and M7 each add their own `CNAME`/`A` record when their respective resource exists.

## Alternatives considered

- **Public hosted zone** — rejected. It would need a real registered domain to be authoritative on the public internet (already rejected on cost grounds in ADR-011), and would expose internal service naming outside the VPC for zero benefit — nothing outside this VPC has any legitimate reason to resolve `db.cloudforge.internal`.
- **No DNS layer — reference RDS/Redis endpoint hostnames directly in app config** — rejected. That couples every consumer of "the database" to AWS's own generated hostname format, and breaks the moment the underlying resource is replaced (a new RDS instance gets a new endpoint) even though the logical service the app depends on hasn't changed at all.

## Consequences

- Because the zone is private and scoped per-VPC, `dev` and `prod` can each have their own `cloudforge.internal` zone with the exact same name and no collision — the VPC boundary is what disambiguates them, not a naming suffix.
- M5 and M7 each become a pure additive change: add a DNS record pointing at the new resource's endpoint, no changes needed here or to anything already using this zone.
