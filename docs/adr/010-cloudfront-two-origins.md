# ADR-010: One CloudFront distribution, two origins (ALB now, S3 in M6)

**Status:** superseded by [ADR-025](025-cloudfront-denied-edge-redesign.md)   **Date:** 2026-09-11   **Milestone:** M4

> **2026-09-22:** AWS Support permanently denied CloudFront access for this account (ADR-025).
> This distribution never gets its second origin; the images path moves through the app instead.
> Kept as a record of the design as built and verified through M4-M9, before the denial.

## Context

The end state I want is a single CloudFront distribution serving both API traffic (routed to the ALB) and product images (routed to an S3 bucket with Origin Access Control) under one hostname, rather than splitting them across two distributions with two different domains. The images bucket and its `/images/*` behavior don't exist yet — that's M6 work — but M4 is when the ALB, WAF, and the CloudFront distribution itself need to exist, since M4's whole DoD is proving the CDN → WAF → ALB path works.

## Decision

Build the distribution now with a single origin (the ALB) and two behaviors that both target it: `default_cache_behavior` and an `ordered_cache_behavior` for `/api/*`, both with caching disabled since API responses aren't cacheable. Structure it so M6 is purely additive: a second origin block for S3, and a third behavior for `/images/*`, added without touching the ALB-facing behaviors at all.

## Alternatives considered

- **Two separate distributions, merge into one later** — rejected. That means two hostnames to reference from the app and docs today, then discarding one and rewiring everything to the survivor in M6 — more total churn than building the real target shape now and filling in the second origin when it exists.
- **Wait until M6 to create the distribution at all, once both origins are ready** — rejected. M4's DoD and evidence (WAF rules, the SQL-injection block screenshot, the CDN-vs-direct-ALB curl comparison) are entirely about the CDN/WAF/origin-lockdown story, none of which needs images. Delaying CloudFront's creation by two milestones would block M4 for a reason that has nothing to do with M4.

## Consequences

- Checkov flags `CKV_AWS_305`/`CKV_AWS_310` (no origin failover group configured) on this distribution today. That's accepted and documented in `.pre-commit-config.yaml`'s skip list — an origin group has nothing to fail over to with exactly one origin, and adding a second origin purely to satisfy that check would mean standing up the S3 bucket two milestones early for no functional reason.
- When M6 adds the S3 origin, it gets its own cache policy (long TTL, compression) distinct from the `CachingDisabled` policy the API behaviors use — the two origins have fundamentally different caching needs, which is exactly why this is one distribution with multiple behaviors rather than one behavior trying to serve both.
