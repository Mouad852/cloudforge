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
