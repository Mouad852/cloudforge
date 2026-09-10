# ADR-021: Long-lived access key, kept over IAM Identity Center

**Status:** accepted   **Date:** 2026-09-05   **Milestone:** M0

## Context

M0's plan was to replace the `cloudforge-admin` IAM user's long-lived access key with IAM Identity Center (AWS SSO), giving short-lived, auto-expiring credentials instead of a permanent key sitting in `~/.aws/credentials`.

Enabling IAM Identity Center requires the account to belong to an AWS Organization. This account doesn't have one yet, and the console's own confirmation screen states plainly that creating an organization **immediately upgrades the account from Free Plan to Paid Plan and expires all remaining free-tier credits** — in this case, the full **$158** balance (the $100 signup credit plus 3×$20 Explore AWS credits), all otherwise valid until 2027-09-02.

## Decision

Keep the existing long-lived access key on `cloudforge-admin`. Do not enable IAM Identity Center for this project.

## Alternatives considered

- **IAM Identity Center / SSO** — the better security practice (short-lived, auto-expiring credentials, no permanent secret to leak). Rejected here specifically because of the forced-upgrade side effect: the cost of gaining this one security nicety is the entire remaining credit balance, on a project whose entire cost strategy (§4) is built around spending as little of that balance as possible. Not a reasonable trade.
- **Delete and recreate the key periodically without Identity Center** — partially adopted as the mitigation (see Consequences).

## Consequences

- The access key remains long-lived. Mitigated by discipline, not tooling: the key is never committed (enforced by `gitleaks` in pre-commit and CI regardless), rotated periodically over the life of the project, and deleted entirely once the account is torn down at project end.
- This is a deliberate cost-vs-practice tradeoff, not an oversight — worth being able to explain in an interview: "I chose not to adopt short-lived credentials here because the AWS console's own upgrade path would have forfeited the project's entire credit budget to get them, and the long-lived key is manageable with basic hygiene at this scale."
- If a future AWS account (e.g., a job's own AWS account, not a personal credits account) makes this trade-off differently — because credits aren't the binding constraint there — Identity Center is the right default to reach for immediately, not an afterthought.

## Update — moved from per-session environment variables to a persisted profile

For the first few weeks I was setting `$env:AWS_ACCESS_KEY_ID`, `$env:AWS_SECRET_ACCESS_KEY`, and `$env:AWS_DEFAULT_REGION` by hand in every new PowerShell terminal, since Windows doesn't persist environment variables across sessions the way a `.bashrc` would. That's not what this ADR actually requires — the decision here is "keep a long-lived key," not "never write it to disk" — so during M4 I switched to a standard AWS CLI named profile instead, via `aws configure`. This writes to `~/.aws/credentials`, which both the AWS CLI and Terraform's AWS provider read automatically with no environment variables needed at all. The file lives outside the repo, protected by normal Windows file permissions, so it doesn't change anything about what gets committed — `gitleaks` still enforces that.

While making the switch I ran into a real bug worth recording: my first `aws configure` attempt stored an access key that didn't match anything in IAM (`aws sts get-caller-identity` failed with `InvalidClientTokenId`). I confirmed it wasn't an environment variable shadowing the profile (`Test-Path Env:\AWS_ACCESS_KEY_ID` was `False` in a fresh terminal), then compared the masked key suffix `aws configure list` showed against the real active key in the IAM console — they didn't match, which meant the key had simply been mistyped during entry, not a permissions problem. Rather than retry typing it a third time, I issued a brand-new access key pair from the IAM console, downloaded the CSV, and pasted those values directly into `aws configure` instead of retyping them. Once `aws sts get-caller-identity` confirmed the new key worked, I deactivated the old one in the IAM console — which is exactly the "rotated periodically" mitigation this ADR already committed to, just triggered earlier than planned by a typo instead of on a schedule.

Consequence: region now also persists via one line added to my PowerShell profile (`$env:AWS_DEFAULT_REGION`), so a new terminal needs zero manual setup before running Terraform or the AWS CLI.
