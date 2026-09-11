# ADR-011: No custom domain — the free `*.cloudfront.net` certificate

**Status:** accepted   **Date:** 2026-09-11   **Milestone:** M4

## Context

Getting HTTPS on a custom domain in front of CloudFront means registering a domain, running a public Route 53 hosted zone for it, requesting an ACM certificate, validating it via DNS, and attaching that certificate to the distribution's viewer configuration. That's real recurring cost (domain registration, typically $12+/year) and setup overhead for a portfolio project with no production traffic and a defined end date, on an account whose entire cost strategy (per the budget decisions in this project) is to spend as little of the credit balance as possible.

## Decision

Use CloudFront's own default certificate instead: `viewer_certificate { cloudfront_default_certificate = true }`. HTTPS is then available immediately at the auto-assigned `<distribution-id>.cloudfront.net` hostname, at zero cost and with nothing to renew or validate.

## Alternatives considered

- **Register a domain and use ACM** — rejected on cost and lifecycle grounds. Paying for a domain that outlives a project explicitly designed to be torn down at the end doesn't buy anything real here; the milestone's DoD only needs a working HTTPS URL, not a branded one.
- **Self-signed certificate** — not a realistic option with CloudFront's viewer certificate settings in the way ACM or the default certificate are, and it would fail browser/client trust anyway, defeating the point of proving HTTPS works.

## Consequences

- The distribution is locked to `TLSv1` as its minimum protocol version — the default certificate can't enforce a higher floor the way a custom ACM certificate on a dedicated hostname could. Checkov's `CKV_AWS_174`/`CKV2_AWS_42` findings on this are accepted and documented in `.pre-commit-config.yaml`'s skip list: that floor is this ADR's actual trade-off, not something overlooked.
- The public-facing hostname is an unbranded `*.cloudfront.net` address, not something memorable. Acceptable here — this project's evidence is about infrastructure behavior (CDN, WAF, origin lockdown), not about presenting a consumer-facing brand.
- If a later milestone or a different account ever needs a real domain (e.g. because the credit-budget constraint that drove this decision doesn't apply), adding one is additive: a new `aws_acm_certificate` plus updating `viewer_certificate` and adding an `aliases` block, without touching anything else in this distribution.
