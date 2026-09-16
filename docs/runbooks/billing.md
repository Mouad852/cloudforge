# Runbook — Billing budget exceeded

**Alarm:** `dev-cloudforge-billing`
**Fires when:** `EstimatedCharges` exceeds the configured project budget (`$20`,
`var.billing_budget_usd`). Checked every ~6 hours (the metric's own native reporting
cadence — not configurable to a tighter period).
**Severity:** Page now — this account has no 12-month free tier (PLAN.md §11.4); every
running hour draws down a finite, real budget.

---

## What it means

`AWS/Billing` → `EstimatedCharges` is AWS's own running total for the account, and it
**always publishes into `us-east-1`** regardless of which region the billed resources
actually run in — this alarm's `provider = aws.use1` exists specifically for that reason,
not by mistake. This is an account-wide number, not scoped to one environment — if both
`dev` and any other ephemeral environment are running at once, both contribute to the
same figure.

## Likely causes

- An environment was left running longer than intended (the whole point of the
  ephemeral-environment strategy in PLAN.md §2 is that nothing should run 24/7).
- A resource wasn't fully torn down by `terraform destroy` and is quietly still billing
  — NAT Gateways, unattached EBS volumes, and idle Elastic IPs are the classic culprits
  (see `docs/runbooks/account-teardown.md` Phase 6 and 7).
- Genuine, expected usage simply grew past the current budget figure as more milestones'
  infrastructure came online — not every trip of this alarm is a leak.

## Diagnose

1. **Billing → Cost Explorer** → daily granularity, last 7 days, grouped by **Service**
   — this is ground truth for what's actually costing money, not a guess.
2. **Billing → Bills** → current month-to-date total, compared against the `$20` budget.
3. If costs look higher than expected for what's actually supposed to be running, work
   through `docs/runbooks/account-teardown.md`'s phase list as a checklist for anything
   left behind by an incomplete `terraform destroy`.

## Mitigate

- If something was left running unintentionally: tear it down — either
  `terraform destroy` the environment cleanly, or follow the full manual teardown
  runbook if Terraform state and real AWS state have diverged.
- If the budget figure itself is simply stale (e.g. more milestones' infra now
  legitimately costs more than `$20`/month to run continuously): update
  `billing_budget_usd` in `terraform/environments/dev/main.tf` and document why in the
  commit message — don't just silently raise it without a reason.
- The nightly-destroy automation planned for M8 (`nightly-destroy.yml`) is the long-term
  backstop for "forgot to tear it down" — until that exists, this alarm is the backstop.

## Escalate

If Cost Explorer shows charges from a service that shouldn't exist at all (nothing in
Terraform state references it), treat that as a potential out-of-band resource — created
manually outside Terraform, or a runaway/misconfigured resource — and investigate before
just paying it down.

## Verify resolved

`EstimatedCharges` back under budget on the next ~6-hour check; recovery email arrives
automatically. Note the ~6-hour reporting lag means "resolved" here can take up to 6
hours to show even after the actual fix — don't expect it to clear immediately.

## Related

`docs/runbooks/account-teardown.md` — the manual cleanup procedure this alarm exists to
catch when it hasn't been followed.
