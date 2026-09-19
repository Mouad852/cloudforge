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

## Known issue: the MASQUERADE rule didn't survive a reboot

While building M3, every instance behind the NAT (the ASG's app instances, plus the `ssm_test`
box) silently lost SSM connectivity and internet access at once. The NAT instance itself
looked completely healthy — running, correct route table pointing at its ENI,
`source_dest_check` disabled, IAM role attached, `net.ipv4.ip_forward = 1` set. Nothing was
wrong with the network path; the actual MASQUERADE rule was simply gone from
`iptables -t nat -L POSTROUTING`.

Root cause: `iptables` rules added by a bare shell command exist only in kernel memory — they
are never written to disk on AL2023 (no `iptables-services` installed). User-data only runs
on an instance's *first* boot. So the rule was correctly applied when the NAT instance first
launched, and then silently wiped out the moment that instance was rebooted for an unrelated
reason (in this case, to pick up a newly-attached IAM role) — with no error, no log entry
calling out the loss, just every private-subnet instance losing egress at once.

**Fix:** replaced the bare `iptables` command with a small `systemd` unit
(`nat-masquerade.service`, `Type=oneshot`, `RemainAfterExit=yes`) that AWS's own `systemd`
reapplies on every boot, not just the first one. Verified by deliberately rebooting the NAT
instance again afterward and confirming the rule reappeared with zero manual intervention.

The general lesson, not specific to this project: **a firewall rule set by a one-off command
in cloud-init/user-data does not survive a reboot unless something reapplies it on every
boot.** The `eth0`/`ens5` bug above and this one are the same class of mistake twice over —
user-data is easy to treat as "runs once, done forever," and it very much does not mean that
for anything living only in kernel state.

## Known issue: the AMI filter matched AL2023's "minimal" variant, which has no `iptables`

While building M5, both app instances and the throwaway `ssm_test` box lost SSM connectivity again, right around when an unrelated `terraform apply` (picking up newer AMIs, the same catalog-drift behavior noted elsewhere in this project) replaced the NAT instance. This time `nat-masquerade.service` failed outright on first boot — `systemctl status` showed the unit's control process exiting immediately, not a rule silently vanishing like the two issues above.

Root cause: the data source's AMI filter (`al2023-ami-*-x86_64`) is a wildcard broad enough to match both AL2023's standard image and its `minimal` variant (`al2023-ami-minimal-<version>-x86_64`) — and this time `most_recent = true` picked the minimal one. The minimal variant doesn't ship `iptables` preinstalled, so the systemd unit's `ExecStart=/usr/sbin/iptables ...` had nothing to execute. Confirmed via `aws ec2 describe-images` on the instance's actual AMI ID, which came back named `al2023-ami-minimal-...`.

**Fix:** added `dnf install -y iptables` to the user-data script, ahead of writing the systemd unit — makes the NAT instance's forwarding setup work regardless of which AL2023 variant the AMI filter happens to match next, rather than trying to make the filter itself variant-proof against AWS's naming changes over time.

Same underlying lesson as the `eth0`/`ens5` bug: user-data that assumes a tool is already present is one AMI refresh away from silently not being true anymore. Three for three now on "the NAT instance's user-data assumed something that wasn't actually there" — worth treating that whole script as the single most fragile piece of this project's infrastructure, not a one-off annoyance.

## Known gap (M9): prod runs the NAT instance too, and AMI releases no longer replace it

**The gap.** The Decision above says prod gets a NAT Gateway, and PLAN.md's M9 rule lists `nat_type` as one of the things dev and prod may differ in. Neither is true of the code: `terraform/modules/network` has only the NAT instance path, with no `nat_type` input, and prod was built on 2026-09-16 with the same instance as dev. The "add the gateway when prod is built" step in Consequences was never done. Today dev and prod differ in sizes, counts, `multi_az`, retention and deletion protection, but not in `nat_type`.

**Why it is deferred, not built.** A NAT Gateway is about $0.045 an hour, roughly $1.08 a day, for as long as prod exists, on top of the rest of prod. Prod is meant to be up only for game-day sessions, and the account is on a fixed credit balance, so the gateway would be the single largest line item of an environment that runs for hours. Building the switch also means real work with real risk: a `nat_type` variable, `count` on the instance and its EIP, an `aws_nat_gateway` with its own EIP in `public-a`, the private route pointing at `nat_gateway_id` instead of the instance's network interface, `moved` blocks so dev's live instance is not destroyed, and tests for both paths. It is left until a game day that needs an HA egress path, and until then prod's egress is a single point of failure, exactly as this ADR says of dev.

**One thing that is fixed.** The fourth known issue above, the AMI filter drifting under `most_recent = true`, was really a broader problem: any new AL2023 release made an unrelated `terraform plan` show the NAT instance as a replacement, and applying it cut all private-subnet egress while the instance was rebuilt. `aws_instance.nat` now has `lifecycle { ignore_changes = [ami] }`, so a replacement is something you choose (`terraform apply -replace=module.network.aws_instance.nat`), not something that happens on whatever apply comes next. A mocked-provider test (`tests/nat_ami.tftest.hcl`) applies twice with different AMIs and asserts the running instance keeps the first one. The app fleet's launch template is deliberately not covered: a new AMI there rolls out through an instance refresh, which keeps capacity up.
