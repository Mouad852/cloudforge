# Traffic Flow — WAF associated directly with the ALB (redesigned, ADR-025)

**Status: applied to `dev` and `prod`, verified 2026-09-24/25** (results at the bottom). This
replaces the M4 CloudFront lockdown diagram after AWS Support permanently denied CloudFront access
(ADR-025). The SQL-injection rule group in the WAF box was added to the code on 2026-09-25, after
that testing found the WAF had none, and is not yet applied.

The interesting part is what changed, not just what the new picture looks like: there used to be
two layers between the internet and the ALB (a security-group prefix list, then a secret header
only CloudFront could inject) because the security group alone could only prove a request came
from *some* CloudFront distribution's shared edge network, not this one specifically. With no
CloudFront, that whole problem disappears along with its solution — the ALB is simply the public
edge now, the way any internet-facing ALB with no CDN in front of it works, and the WAF is
associated with it directly.

```mermaid
flowchart TB
    Viewer(("Legitimate client"))
    Malicious(("Malicious request<br/>e.g. SQLi in a query param"))

    SG{"ALB security group<br/>ingress: 0.0.0.0/0 on port 80 (ADR-025 —<br/>deliberate: this is now the public edge)"}
    WAF{{"AWS WAF, REGIONAL scope<br/>associated directly with the ALB<br/>CommonRuleSet · KnownBadInputs ·<br/>IP Reputation · rate limit 2000/5min/IP ·<br/>SQLiRuleSet"}}
    WAFBlock[["Blocked by the WAF<br/>never reaches the listener"]]

    Listener{"ALB listener :80<br/>default action: weighted forward (ADR-017)"}

    TG["Target groups: blue + green<br/>weighted 100/0 by default"]
    ASG_A["EC2 · ASG · AZ-A"]
    ASG_B["EC2 · ASG · AZ-B"]

    Viewer --> SG
    Malicious --> SG
    SG -->|"port 80, any source -<br/>nothing left to narrow this to"| WAF
    WAF -->|blocked| WAFBlock
    WAF -->|allowed| Listener
    Listener --> TG
    TG --> ASG_A
    TG --> ASG_B
```

## Why one layer is now correct, where two were needed before

The old two-layer design (`docs/adr/014-alb-locked-to-cloudfront.md`, superseded) existed because
a security-group rule scoped to CloudFront's origin-facing prefix list only proves a request came
from CloudFront's shared edge network — a range every CloudFront customer on AWS uses, including
someone else's distribution pointed at this ALB's DNS name as a custom origin. The secret header
was the actual authorization boundary, proving the request came through *this* distribution.

None of that reasoning applies once the ALB has no CloudFront in front of it to narrow the field
to in the first place. It receives the whole internet on port 80 by design (ADR-025), and the WAF
web ACL is what actually filters traffic before it reaches the listener. It carries the same four
rules the old CloudFront-scoped one had, now at `REGIONAL` scope and attached with
`aws_wafv2_web_acl_association`, plus `AWSManagedRulesSQLiRuleSet`. That fifth rule was added on
2026-09-25, because none of the original four matches SQL injection.

## Verified 2026-09-24/25, on `dev` and `prod`

- `curl http://<alb-dns-name>/api/products` returns `200` with JSON, from the internet.
- `aws wafv2 get-web-acl-for-resource --resource-arn <alb-arn>` returns
  `<env>-cloudforge-alb-waf` on both environments.
- `aws cloudfront list-distributions` is empty: nothing CloudFront-related is left.
- The WAF's sampled requests show real traffic being filtered: ordinary requests allowed, and
  scanner traffic from unrelated IPs blocked by `CommonRuleSet`'s `UserAgent_BadBots_HEADER` rule.
- **SQL injection was not blocked.** A request with `' OR '1'='1` in the query string, sent from
  AWS CloudShell, passed the WAF and got `200` from the app. That finding is why
  `AWSManagedRulesSQLiRuleSet` exists. Still to verify once it is applied: the same request gets
  `403`, and the sampled requests name that rule group.

**Test SQL injection from CloudShell, not from your own machine.** From the operator's network,
every request containing an SQL-injection pattern got a TCP connection reset, and the WAF's
sampled requests showed none of them ever arrived. Something on that network path (security
software, the router, or the network's own firewall) drops them before they leave. Because the
ALB is plain HTTP (G11), anything on the path can read the full URL. A reset from your own machine
therefore says nothing about the WAF.

See ADR-025 (`docs/adr/025-cloudfront-denied-edge-redesign.md`) for the full context and decision,
ADR-006 (why the health check behind the target groups is shallow), and ADR-017 (the weighted
blue/green forward this listener's default action now carries directly).
