# ADR-025: CloudFront access permanently denied — the ALB becomes the public edge

**Status:** accepted   **Date:** 2026-09-22   **Milestone:** M10

## Context

The AWS Support case referenced in the M6/M8 status notes (`AccessDenied: Your account must be
verified before you can add new CloudFront resources`) was resolved on 2026-09-22, not by
clearing, but by a written denial:

> After completing our internal review, I regret to inform you that we are unable to approve
> access to CloudFront resources on your account at this time. Access to certain AWS services,
> including CloudFront, requires an established history of AWS service usage and on-time
> billing. [...] Eligibility can change over time with continued usage and account history.

There is no appeal, override, or paid tier that grants access faster — the stated path is
"keep using the account, keep paying on time, then submit a new request." With roughly a month
of milestones left (M10–M12) and an account a few weeks old, waiting for that history to build
would stall the project on something outside its control, for an unknown and possibly long time.

Up to this point, CloudFront was load-bearing in three places, not just the WAF's home:

- **ADR-014** locked the ALB down so only requests arriving through *this* CloudFront
  distribution would be forwarded — a security-group prefix-list rule plus a secret header
  CloudFront injected and the ALB listener checked for.
- **ADR-011** chose "no custom domain" specifically because CloudFront's default
  `*.cloudfront.net` certificate gave free HTTPS with nothing to buy or renew.
- **ADR-010**'s single distribution served both API traffic (to the ALB) and product images
  (from S3, via Origin Access Control) under one hostname.

None of that can exist without a CloudFront distribution.

## Decision

Redesign the edge without CloudFront. The ALB becomes the public edge itself:

- **WAF moves to `REGIONAL` scope**, associated directly with the ALB via
  `aws_wafv2_web_acl_association`, instead of `CLOUDFRONT` scope attached to a distribution. Same
  four rules (`AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`,
  `AWSManagedRulesAmazonIpReputationList`, the per-IP rate limit) — only where they attach
  changes. A `REGIONAL` web ACL lives in the ALB's own region, so this also removes the need for
  the `aws.use1` provider in `modules/edge` — that provider now exists only for observability's
  billing alarm, which was never related to CloudFront.
- **The ALB's security group accepts the internet directly** on port 80. There is nothing left to
  narrow it to — the prefix-list-plus-secret-header lockdown (ADR-014) existed to prove a request
  came through CloudFront specifically; with no CloudFront, the ALB *is* the front door, the same
  way any public ALB with no CDN in front of it works. ADR-014 is superseded.
- **The ALB stays HTTP-only. No domain is purchased.** Real HTTPS on an ALB needs a certificate
  bound to a domain name — ACM won't issue one for an AWS-generated `*.elb.amazonaws.com` name.
  Buying a domain was considered and declined: it reopens the recurring cost ADR-011 avoided, for
  a portfolio project with a defined end date. This is a real regression from HTTPS-everywhere,
  accepted deliberately, not overlooked. ADR-011 is superseded by this trade instead of its
  original one.
- **CloudFront's response-headers policy is gone**, and an ALB cannot rewrite headers on
  forwarded traffic — only on its own fixed-response actions. `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY` and `Referrer-Policy: same-origin` move into the Go app as middleware.
  **`Strict-Transport-Security` is dropped, not moved.** HSTS tells a browser to use HTTPS only
  for this host from now on; sending it over an HTTP-only site would be actively wrong, not a
  smaller version of the same protection.
- **Images are served through the app**, not a public bucket or presigned URLs. A new
  `GET /api/products/{id}/image` route streams the object from S3 using the same IAM role the
  app already has (`s3:GetObject` on the images bucket, granted since M3). The alternative —
  making the bucket public, or handing out presigned URLs — was rejected: every other bucket in
  this project blocks public access on purpose, and presigned URLs would let image traffic skip
  the WAF and the rate limit entirely. Routing through the app keeps the "everything reachable
  through one WAF-protected edge" shape the rest of the project already has. The images bucket's
  policy moves from `modules/edge` (which needed the distribution's ARN for the OAC condition) to
  `modules/storage`, matching the artifacts bucket's own TLS-only policy — the circular-dependency
  reason for keeping it in `edge` no longer applies once there is no distribution ARN to reference.
- **The Synthetics canary hits the ALB directly**, over HTTP. It used to hit CloudFront
  specifically because ADR-014 made the ALB 403 anything else; there is no longer a reason not to
  hit the ALB, since it is the actual public entry point now.

## Alternatives considered

- **Wait and reapply once account history builds.** AWS's own suggested path. Rejected as the
  primary plan, not because it's wrong — it may well be the right call in a few months — but
  because it has no predictable timeline and would stall M10–M12 on something outside this
  project's control. Nothing here prevents reapplying later; if CloudFront access is ever granted,
  bringing it back is additive work on top of the redesigned edge, not a reversal of it.
- **A third-party CDN in front of the ALB** (e.g. Cloudflare's free tier) to keep the
  CDN-plus-WAF shape without CloudFront specifically. Rejected: it still needs a domain, adds a
  dependency outside AWS and outside Terraform's `aws` provider to a project whose whole premise
  is AWS and Terraform, and is more total new work than moving the WAF to `REGIONAL` scope — which
  is itself a real, standard, fully AWS-native pattern, not a downgrade.
- **Make the images bucket public and drop the app-proxy route.** Simpler, but a direct
  contradiction of the public-access-block-on-everything stance every other bucket in this project
  takes, and it would let image traffic bypass the WAF entirely.

## Consequences

- **Superseded:** ADR-010 (one distribution, two origins — there is no distribution), ADR-011 (no
  custom domain, for CloudFront's free certificate — the decision not to buy a domain stands, but
  the reasoning and the result, HTTP-only, are different now) and ADR-014 (the CloudFront lockdown
  — nothing left to lock the ALB behind). Each of those files now carries a status line pointing
  here; their history stays as a record of what was built and why it needed to change, not deleted.
- **The threat model and encryption inventory** (`docs/security/`) need every CloudFront-dependent
  row rewritten: there is no viewer-to-CloudFront TLS hop, no CloudFront-to-ALB plaintext gap (G1)
  in its old form, and the ALB's world-facing ingress is now the design, not an exception to flag
  as a future risk.
- **A new, permanent Checkov exception.** The ALB security group's `0.0.0.0/0` ingress on port 80
  is now deliberate and structural, not a mistake — it is this project's one documented exception
  to "no security group opens to the world," the same way the NAT instance's world-facing egress
  already is. `CKV_AWS_260` is added to the skip list for it.
- **Every CloudFront-dependent screenshot already captured for M4, M6, M8 and M9** (WAF rules on
  CloudFront, the CDN-vs-direct-ALB comparison, the `/images/*` behavior, cache-hit ratio) stands
  as historical evidence of what was actually built and verified before this denial — not
  retracted, but no longer describes the current architecture. `PLAN.md`'s evidence lists for
  those milestones are now stale in the same way; updating them is a separate, later task.
- **If CloudFront access is ever granted later**, re-adding it is additive: a distribution with an
  ALB origin and an OAC-fronted S3 origin, same shape as before, laid on top of an edge that
  already works correctly without it — not a prerequisite this project is blocked on a second time.

> **2026-09-25:** Applied to `dev` and `prod` and tested with real requests. The testing showed
> that "same four rules" was not enough: none of them matches SQL injection
> (`AWSManagedRulesCommonRuleSet` has no SQL-injection rules), and a request with
> `' OR '1'='1` in the query string reached the app with a `200`. `AWSManagedRulesSQLiRuleSet`
> was added as a fifth rule. See T2 in `docs/security/threat-model.md`.
