# Security incident response

What happens when something goes wrong with CloudForge's security or availability: how an
incident is classified, who acts, what evidence exists, and step-by-step playbooks for the
incidents most likely to happen here. Written in M10 for the Well-Architected review (SEC 10,
OPS 10, OPS 7). The playbooks have not been rehearsed yet; that is M12's game days.

Availability incidents already have one runbook per alarm in `docs/runbooks/`. This plan adds
the process around them, and the security incidents no alarm covers.

---

## Severity

| Level | Meaning | Examples | Response |
|---|---|---|---|
| **SEV1** | Prod is down, data or credentials are exposed, or someone else has access to the account. | `service-degraded` firing on prod; a leaked access key; an Access Analyzer finding for a public resource; an instance behaving as if compromised. | Drop everything. Contain first, investigate second. |
| **SEV2** | Prod is degraded, or the availability SLO's error budget is burning fast. | One prod alarm firing; a WAF rule blocking legitimate traffic; an unexpected cost spike. | Same day. |
| **SEV3** | No user impact: dev only, or a warning. | A dev alarm; a drift issue; a failed nightly job. | Next working session. |

The SLOs in `docs/observability/slo.md` (99.5% availability, 99.9% correctness) decide the
difference between SEV1 and SEV2 for availability: an outage that breaches the month's error
budget is SEV1.

## People and contacts

This is a one-person project, so the owner is the incident commander, the responder and the
communicator.

| Who | For what | How |
|---|---|---|
| Owner (GitHub `Mouad852`) | Everything | Alarm emails from SNS; GitHub issues from the drift check |
| AWS Support | Account and billing questions (Basic plan: no technical support) | AWS console → Support Center |
| AWS Trust & Safety | Suspected account compromise or abuse | "Report suspicious activity" in the AWS console, or `abuse@amazonaws.com` |
| GitHub Support | A compromised GitHub account or repository | github.com/contact |

## Access prepared in advance

| Access | What it is for | Where it is |
|---|---|---|
| `cloudforge-admin` access key | Day-to-day CLI and Terraform; containment commands below | AWS CLI profile on the owner's machine (ADR-021) |
| Root user with MFA | Break-glass: when the admin key itself is compromised or deleted | Root email and password, plus the MFA device |
| SSM Session Manager | A shell on any instance, with no SSH and no open port (ADR-005) | Through the admin key: `aws ssm start-session --target <instance-id>` |
| GitHub repository admin | Revoking CI's access by disabling workflows | The owner's GitHub account |

If the admin key is the thing that leaked, **use root with MFA** to deactivate it, then create a
new key.

## Evidence that already exists

| Source | What it answers | How long it is kept |
|---|---|---|
| CloudTrail `management-events` (all Regions) | Who called which AWS API, from where | Event history 90 days; the S3 copy indefinitely |
| VPC flow logs `/aws/vpc/<env>-cloudforge` | Which IPs talked to which instances, on which ports | 30 days (prod), 14 (dev) |
| ALB access logs (S3) | Every HTTP request: client IP, path, status, user agent | 90 days |
| App logs `/cloudforge/<env>/app` | Every request the app handled, with its request ID | 30 days (prod), 14 (dev) |
| WAF sampled requests | Requests the WAF matched, blocked or allowed | **3 hours only**: capture them first |
| IAM Access Analyzer `cloudforge-account` | Anything newly shared outside the account | While the finding is active |
| Drift check (`drift.yml`, daily) | Resources changed outside Terraform | GitHub issue |

**Before changing anything, write down the time and what you saw**, and capture any evidence
that is about to disappear (WAF samples, a running instance's memory and disk). Keep the notes
for the post-incident review.

## The process

1. **Detect.** An alarm email, a drift issue, an Access Analyzer finding, a billing alarm, or
   something noticed by hand.
2. **Triage.** Decide the severity with the table above. Open a GitHub issue titled
   `Incident: <what>` and keep the timeline in it.
3. **Contain.** Stop the damage from growing, using the playbook below. Containment comes before
   finding the cause.
4. **Preserve evidence.** Snapshot, export or copy what the investigation will need before
   eradication destroys it.
5. **Eradicate.** Remove what caused it: rotate the credential, delete the exposure, replace the
   instance.
6. **Recover.** Bring the service back and confirm it with the checks in
   `docs/runbooks/deployment.md` ("After deploying").
7. **Learn.** Within a week, write a post-incident review (template at the end) and turn each
   lesson into a change, an ADR or a runbook update.

## Playbooks

### P1 — An AWS access key leaked

Signs: GitHub secret scanning or gitleaks flags a key, AWS emails about an exposed key, or
CloudTrail shows calls you did not make.

1. **Contain:** deactivate the key immediately:
   `aws iam update-access-key --user-name cloudforge-admin --access-key-id <key> --status Inactive`.
   If that key is the one you are using, sign in as **root with MFA** and deactivate it in the
   IAM console.
2. **Preserve:** in CloudTrail event history, filter on **Access key** = the leaked key and
   export every event from the time of the leak.
3. **Investigate:** list what those calls created or changed: new IAM users, keys or roles,
   instances in any Region (check all Regions, including unused ones), changed policies.
4. **Eradicate:** delete anything the attacker created, delete the leaked key, and create a
   new one (ADR-021's rotation).
5. **Recover:** run `terraform plan` for `bootstrap`, dev and prod, and the drift check, to
   confirm nothing Terraform manages was changed.
6. Watch the billing alarms for the next days. Cryptomining on stolen keys shows up there first.

### P2 — Access Analyzer reports external access

Signs: a new active finding in IAM → Access analyzer → Resource analysis.

1. **Triage:** read the finding. Is it public or one specific account? What resource? Was it
   created by Terraform (it has the `ManagedBy = terraform` tag) or by hand?
2. **Contain:** remove the access. For an S3 bucket, re-enable the public access block; for a
   snapshot, remove the share; for a role, remove the outside principal from its trust policy.
3. **Investigate:** CloudTrail shows who changed the policy and when. For S3, the bucket's
   data events are not logged, so assume anything public was read.
4. **Eradicate:** if the change came from Terraform code, fix the code (a Checkov custom
   policy may be worth adding so it cannot happen again); if by hand, `terraform apply` puts it
   back.
5. If the exposed data was **Confidential or Restricted** (`data-classification.md`), treat it
   as SEV1: rotate any exposed secret (P5).

### P3 — An attack on the public endpoint

Signs: the WAF's blocked-request metrics spike, `alb-latency-p95` or `alb-5xx` fires, or the
bill jumps from traffic.

1. **Preserve first:** WAF sampled requests last 3 hours. In the WAF console, open the web ACL
   `<env>-cloudforge-alb-waf` → Traffic overview → Sampled requests, and save them.
2. **Triage:** from the samples and the ALB access logs, find the source IPs, paths and user
   agents. Is it one IP, many IPs, or requests that pass the WAF?
3. **Contain:** the per-IP rate limit (`waf_rate_limit`, 2,000 requests per 5 minutes) already
   applies. To block specific IPs, add an IP set rule to the web ACL in `terraform/modules/edge`
   and apply, never by hand in the console (the drift check would report it). If legitimate
   requests are being blocked instead, find which rule matched in the samples.
4. **Recover:** the ASG scales out on CPU on its own; check `asg-in-service-instances`.
5. There is no AWS Shield Advanced. A large distributed attack is beyond what this setup can
   absorb; the billing alarms are the backstop.

### P4 — An instance looks compromised

Signs: unexpected outbound connections in the VPC flow logs, unknown processes, CPU with no
traffic behind it, or a CloudTrail call made with the instance role from outside AWS.

1. **Contain without destroying evidence:** do **not** terminate the instance. Take it out of
   service instead, so the ASG launches a clean replacement:
   `aws autoscaling enter-standby --auto-scaling-group-name <env>-cloudforge-app --instance-ids <id> --should-decrement-desired-capacity false`.
2. **Isolate it:** create an empty security group in the VPC, with no inbound rules and its
   default outbound rule removed, and make it the instance's only security group. SSM keeps
   working only if the instance can reach its endpoints, so capture what you need first.
3. **Preserve:** snapshot its root volume
   (`aws ec2 create-snapshot --volume-id <vol> --description "incident <date>"`), and if
   possible run `ps`, `ss -tnp` and a copy of `/var/log` through SSM first.
4. **Investigate:** CloudTrail filtered by the instance's role session; VPC flow logs for its
   private IP.
5. **Eradicate:** terminate it once evidence is saved. If the instance role's credentials were
   used from outside AWS, revoke its sessions: IAM → Roles → the role → "Revoke active
   sessions".
6. **Recover:** the replacement comes from the same launch template and binary, so find how
   it was compromised before assuming the replacement is safe.

### P5 — A database or cache credential leaked

1. **RDS master password:** it is managed by RDS in Secrets Manager (ADR-009). Rotate it:
   `aws secretsmanager rotate-secret --secret-id <the rds!db-... secret>`, then run an instance
   refresh so the app fetches the new value (it reads the secret at startup).
2. **Redis AUTH token:** it is generated by Terraform. Force a new one:
   `terraform apply -replace="module.cache.random_password.redis_auth"` in the environment's
   root, then refresh the instances. From an SSM session, confirm the old token is rejected.
3. Both are only reachable from the app's security group, so a leak alone does not expose the
   data. Check the VPC flow logs for connections to ports 5432 or 6379 from anything else.
4. The Redis token is also in Terraform state (`encryption-inventory.md`, G7): if the state
   bucket is what leaked, treat it as P1 as well.

### P6 — An unexpected cost spike

Signs: the `$15` account-wide or `$20` prod billing alarm, or the credit balance dropping
faster than expected.

1. **Triage:** Cost Explorer, grouped by Service and then by the `Project` and `Environment`
   tags. Is the cost tagged (ours, grown) or untagged (created outside Terraform)? Grouping by
   tag only works once those tags are activated as cost allocation tags in Billing, and only
   for costs from after the activation.
2. **Contain:** if dev is up and not needed, destroy it (`nightly-destroy` → Run workflow).
   Stop or delete any untagged resource you do not recognise, and check every Region.
3. Untagged resources in unused Regions, especially GPU instances, mean a leaked credential:
   switch to **P1**.

## Post-incident review template

Save as `docs/incidents/<YYYY-MM-DD>-<short-name>.md`:

```markdown
# <Short name> - <date>

**Severity:** SEV<n>   **Duration:** <detected> to <resolved>   **Impact:** <who or what was affected>

## Timeline (UTC)
- hh:mm - what happened / what was done

## What happened, and why
## What went well
## What went badly, or was lucky
## Changes made because of this
- [ ] change, with a link to the commit, ADR or runbook
```

No blame, including self-blame: the question is what the system allowed to happen, not who did
it.

## Known gaps

- **Never rehearsed.** The playbooks are written, not practised. M12's game days run at least
  one security scenario.
- **No automated detection** for P1 and P4: GuardDuty would flag leaked-key use and suspicious
  instance traffic, but the Free plan does not include it (`well-architected.md`, SEC 1).
- **No forensic tooling** beyond EBS snapshots and SSM: no memory capture and no isolated
  forensics account.
