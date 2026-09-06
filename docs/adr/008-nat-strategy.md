# ADR-008: NAT Gateway in prod, NAT instance in dev

**Status:** accepted   **Date:** 2026-09-06   **Milestone:** M1

## Context

Private subnets (`app`, `data`) need outbound internet access for things like OS package updates, without being reachable from the internet themselves. AWS's managed answer is a NAT Gateway — highly available within its AZ, zero maintenance, billed per hour plus per-GB processed (~$32-33/mo just sitting idle in `eu-west-3`). The alternative is a self-managed NAT instance: a regular EC2 box with IP forwarding and a MASQUERADE rule, billed as a normal instance (a `t3.micro` is a few dollars a month).

This project runs on a fixed personal credit balance (see PLAN.md §4), and `dev` in particular is meant to be disposable — spun up to demo or test against, torn down when not in use (ADR-012). Paying gateway rates for an environment that is not always running is the wrong trade.

## Decision

- **`dev`**: NAT **instance** — a `t3.micro` in a public subnet, `source_dest_check` disabled, with `net.ipv4.ip_forward` and an iptables `MASQUERADE` rule set via user-data. One instance, one point of failure, acceptable for a non-HA dev box.
- **`prod`** (when that environment is built): NAT **Gateway** — managed, HA within its AZ, no instance to patch.
- Both environments also get an **S3 gateway VPC endpoint**, which is free and routes S3 traffic (including Terraform's own state reads/writes) around the NAT entirely — cutting both the per-GB NAT charge and one more thing that would otherwise depend on the NAT instance being healthy.

Only the `dev` half exists in code today (`terraform/modules/network`, NAT instance + S3 endpoint + private route table, all `for_each`/single-resource, no `nat_strategy` switch yet). The NAT Gateway path gets added to the module when `prod` is actually built, not speculatively now.

## Alternatives considered

- **NAT Gateway everywhere** — simplest to write, but ~$32-33/mo per environment left running would burn through the credit balance for infrastructure that is idle most of the time.
- **Interface VPC endpoints for every AWS service the app touches** — avoids NAT for those specific services, but each interface endpoint is itself ~$7.30/mo (plus per-GB), which is worse than a single NAT instance for a project with only a handful of AWS API dependencies. The one interface-free option that's unambiguously worth it regardless of NAT strategy — the **S3 gateway endpoint** — is taken either way, since it's free.
- **NAT instance everywhere (including prod)** — cheaper, but a single EC2 box is a real single point of failure and a real patching burden for an environment meant to demonstrate production practice.

## Consequences

- `dev`'s outbound path depends on one EC2 instance staying up; if it's stopped or terminated, `app`/`data` subnets lose internet access until it's replaced. Acceptable for a throwaway dev environment, not for prod.
- The NAT instance's user-data only sets up forwarding on first boot — a `terraform apply`-driven replacement re-runs it correctly, but a manual stop/start of the same instance would not (not a concern here since the instance is never touched outside Terraform).
- When `prod` is built, the network module needs a real fork in it (`nat_strategy = "instance" | "gateway"` or two environments simply passing different module inputs) — deferred to that milestone rather than built and left untested now.

## Known issue: hardcoded interface name broke forwarding

While bringing up the throwaway SSM test instance (private subnet, `app-a`), it could never register with SSM — `SSM Agent unable to acquire credentials ... dial tcp ...:443: i/o timeout`. Status checks on the instance itself passed, and the IAM role was attached correctly, so the failure was on the network path, not IAM.

Root cause: the NAT instance's user-data ran `iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`, but Amazon Linux 2023 on Nitro-based instances (including `t3.micro`) names its network interface `ens5`, not `eth0`. The rule silently matched nothing, so packets forwarded *from* other hosts were never source-NAT'd. This was easy to miss because the NAT instance's *own* outbound traffic (NTP sync, background port-scan noise visible in the flow logs) worked fine regardless — that traffic never goes through the POSTROUTING/forwarding path at all, only genuinely forwarded traffic does.

**Fix:** dropped the `-o eth0` qualifier entirely (`iptables -t nat -A POSTROUTING -j MASQUERADE`) — a single-NIC instance doesn't need to name the interface. Since EC2 only runs user-data on an instance's first boot, the running NAT instance had to be explicitly replaced (`terraform apply -replace=`) for the corrected script to actually execute, rather than just re-applying the changed config.

This is exactly the kind of operational sharp edge a managed NAT Gateway doesn't have — worth remembering as a concrete point in the instance-vs-gateway trade-off, not just the cost line.
