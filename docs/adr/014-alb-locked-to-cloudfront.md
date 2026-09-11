# ADR-014: ALB locked to CloudFront — prefix list plus a secret origin header

**Status:** accepted   **Date:** 2026-09-11   **Milestone:** M4

## Context

Once CloudFront fronts the ALB, I want the ALB to be unreachable except through CloudFront — hitting the ALB's own DNS name directly should fail. The obvious first step is a security group rule scoping ingress to AWS's managed prefix list `com.amazonaws.global.cloudfront.origin-facing`, which covers CloudFront's edge IP ranges. That rule alone isn't enough: that IP range is shared by every CloudFront distribution on AWS, including ones I don't control. Anyone could point their own CloudFront distribution at this ALB's public DNS name as a custom origin, and the prefix-list rule alone would let that traffic through — it only proves a request came from CloudFront's edge network in general, not from *this* distribution specifically.

## Decision

Two layers, not one:

- The ALB's security group only allows inbound HTTP on port 80 from the `com.amazonaws.global.cloudfront.origin-facing` prefix list — narrows the field from the entire internet down to CloudFront's edge network.
- A `random_password` secret is generated per environment and injected by *this* distribution as a custom origin header (`X-Origin-Verify`). The ALB listener's default action is a fixed `403` response; a listener rule at priority 1 matches specifically on that header value and only then forwards to the target group.

The security group narrows *where* a request can come from; the header proves *which* distribution it actually came through. The header is the real authorization boundary — the prefix list rule is necessary but not sufficient on its own.

## Alternatives considered

- **Prefix-list security group rule alone** — rejected as insufficient for the reason above: it authorizes CloudFront's network in general, not this specific distribution.
- **IP allowlist of CloudFront's published IP ranges instead of the managed prefix list** — rejected; it's the same shared-range problem as the prefix list, plus manual upkeep every time AWS changes the range, which the managed prefix list already handles automatically.
- **AWS WAF on the ALB itself, checking a custom header** — rejected as redundant; WAF is already doing real work on the CloudFront side (managed rule groups plus the rate-based rule), and a listener rule condition does the exact same header check at the ALB for free, with no extra resource or cost.

## Consequences

- Anyone who discovers the ALB's DNS name and sends it a raw request gets a `403 Forbidden` from the default listener action — confirmed directly: a direct `curl` against the ALB DNS name times out at the security-group level before it can even reach the listener, since the request isn't coming from CloudFront's edge network at all in that test.
- The secret header value lives only in Terraform state and inside the CloudFront distribution's origin config — it's never exposed to a client, since CloudFront strips its own custom origin headers before forwarding a response back to the viewer.
- If the secret ever needs to rotate, it's a single `random_password` resource — tainting or replacing it rotates the value used by both the CloudFront origin config and the ALB listener rule condition together, since both reference the same resource.
