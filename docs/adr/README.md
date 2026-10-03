# Architecture Decision Records

This is the project's decision log. Each ADR was written on the day its decision was implemented
and committed with the change it describes, so the log doubles as a timeline of the project's
reasoning. When reality later diverged from a decision, the ADR got a dated status note or a
superseding ADR rather than being rewritten.

| ADR | Decision | Status |
|---|---|---|
| [001](001-state-backend.md) | Terraform S3 backend with native S3 locking | accepted |
| [002](002-state-isolation.md) | Separate state per environment | accepted |
| [003](003-graviton.md) | Graviton (`t4g`) for app, RDS and Redis | accepted |
| [004](004-go-binary-artifact.md) | App artifact = static Go binary in S3, pulled at boot | accepted |
| [005](005-ssm-session-manager.md) | SSM Session Manager for all access | accepted |
| [006](006-shallow-health-check.md) | Shallow ALB health check, deep check monitored separately | accepted |
| [007](007-target-tracking-scaling.md) | Target tracking scaling | partly built — CPU policy only (status note) |
| [008](008-nat-strategy.md) | NAT instance in dev, NAT Gateway in prod | gateway never built — known gap recorded in the ADR |
| [009](009-secrets-manager-rds-password.md) | RDS master password managed by Secrets Manager | accepted, corrected 2026-10-01 (rotation) |
| [010](010-cloudfront-two-origins.md) | One CloudFront distribution, two origins | superseded by 025 |
| [011](011-no-custom-domain.md) | No custom domain | superseded by 025 |
| [012](012-two-ephemeral-environments.md) | Two environments, both ephemeral | accepted — prod not yet ephemeral (status note) |
| [013](013-private-hosted-zone.md) | Route 53 private hosted zone | accepted |
| [014](014-alb-locked-to-cloudfront.md) | ALB locked to CloudFront | superseded by 025 |
| [015](015-snapshot-lifecycle.md) | Snapshot on down, restore on up | accepted |
| [016](016-terraform-native-tests.md) | Terraform native tests for every module | accepted |
| [017](017-bluegreen-second-strategy.md) | Blue/green as a second deploy strategy | built, not yet exercised (status note) |
| 018 | Backup approach | reserved for M11 |
| 019 | Fault-injection approach (AWS FIS is unavailable on this account's plan) | reserved for M12 |
| [020](020-slos-before-gamedays.md) | SLOs defined before game days | accepted |
| [021](021-long-lived-key-over-identity-center.md) | Long-lived admin key over IAM Identity Center | accepted |
| [022](022-redis-tls-servername-decoupled-from-dial-address.md) | Redis TLS server name decoupled from the dial address | accepted |
| [023](023-what-stays-hardcoded-in-modules.md) | What stays hardcoded in modules | accepted |
| [024](024-public-cache-module-is-a-generalised-copy.md) | Public cache module is a generalised copy | accepted |
| [025](025-cloudfront-denied-edge-redesign.md) | CloudFront denied — the ALB becomes the public edge | accepted |
| [026](026-environments-rebuild-themselves.md) | A rebuilt environment brings itself back | accepted |

Start with **025** (an external constraint forcing a redesign), **009** (a decision whose
consequence caused a real outage) and **026** (making a destroyed environment rebuild itself).

## Template

Copy `000-template.md`. Fill it in on the day the decision is implemented, and commit it with
the change it describes.

```markdown
# ADR-0XX: <title>

**Status:** accepted   **Date:** <YYYY-MM-DD>   **Milestone:** MX

## Context
What problem or choice this addresses.

## Decision
What was chosen.

## Alternatives considered
What else was possible, and why it was rejected.

## Consequences
What this makes easier, harder, or costs.
```
