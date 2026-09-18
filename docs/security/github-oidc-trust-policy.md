# GitHub Actions OIDC trust policy

**Module:** `terraform/modules/cicd-oidc`   **Milestone:** M8

CI/CD authenticates to AWS with short-lived credentials issued per workflow run, not a long-lived
IAM user access key stored as a GitHub secret. GitHub Actions requests a JWT from its own OIDC
issuer (`token.actions.githubusercontent.com`), AWS STS exchanges that token for temporary
credentials via `sts:AssumeRoleWithWebIdentity` — nothing durable to leak, rotate, or forget to
revoke when a workflow is retired.

## The provider resource is not the boundary

```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}
```

This resource just tells AWS "trust tokens signed by GitHub's OIDC issuer" — it doesn't say
*which* GitHub repo, branch, or workflow. On its own, it would let any GitHub Actions run
anywhere on GitHub — a different repo, a different org, a stranger's fork — request a token from
the same issuer and attempt to assume any role that trusts this provider. The provider is
necessary but not sufficient. The actual access boundary lives one level down, in each IAM role's
own trust policy `Condition` block, which is checked per `AssumeRoleWithWebIdentity` call against
claims inside the token itself.

## Two claims, two checks

Every role's trust policy checks exactly two claims from the OIDC token:

- **`aud` (audience)** — must equal `sts.amazonaws.com`. This is the intended recipient of the
  token; checking it stops a token minted for some other relying party from being replayed against
  AWS.
- **`sub` (subject)** — identifies the repo and, depending on how the token was requested, the
  branch, environment, or event type that requested it. This is where the real scoping happens.

## Immutable subject claims: not just `repo:owner/repo`

The subject prefix used throughout this module isn't `repo:Mouad852/cloudforge` — it's
`repo:Mouad852@185850806/cloudforge@1358410203`. GitHub turned on *immutable subject claims* for
this repo by default, which bakes the numeric owner and repository IDs into every subject the
token issuer produces, not just their current names. That matters here for a concrete reason, not
a theoretical one: if this repo were ever renamed or transferred, a `sub` condition written as
`repo:Mouad852/cloudforge:...` would silently keep matching tokens for whatever *new* repo now
holds that name — a rename hijack. The immutable form breaks instead of silently keeps trusting,
which is the correct failure mode for a trust boundary.

The exact prefix isn't something to hand-derive — it's fetched once and pinned as a Terraform
variable:

```
gh api repos/Mouad852/cloudforge/actions/oidc/customization/sub
```

`sub_claim_prefix` from that response becomes `github_oidc_subject_prefix`, set in
`terraform/bootstrap/main.tf`. It only changes if the repo is renamed or transferred, at which
point GitHub reissues a new prefix and this must be updated to match — otherwise every OIDC-based
workflow in the repo starts failing to authenticate at once.

## Two roles, scoped by what triggers them

A single role shared by every job would mean a `pull_request` workflow — triggered by anyone who
can open a PR, before any review has happened — has the same AWS access as a job that runs after a
merge to `main`. That's the wrong shape for a CI/CD pipeline that treats `main` as the
review-gated boundary. So there are two roles instead, split by trust condition, not by workflow
file:

**`terraform_plan`** — read-only (`ReadOnlyAccess`), assumed by:
- Any `pull_request`-triggered run (`terraform.yml`'s `plan`/`infracost`/PR-mode `test-readonly`
  jobs — posts a plan as a PR comment without ever granting write access to unreviewed code).
- `drift.yml`'s schedule- and `workflow_dispatch`-triggered runs.

```hcl
StringLike = {
  "token.actions.githubusercontent.com:sub" = [
    "${var.github_oidc_subject_prefix}:pull_request",
    "${var.github_oidc_subject_prefix}:ref:refs/heads/${var.default_branch}",
  ]
}
```

The second entry is there for a reason that isn't obvious from the workflow files themselves: a
`schedule`-triggered run has no pull request and (unless the job sets `environment:`) no
environment either — it always executes against the default branch, and GitHub issues it the
*same* ref-based subject as an ordinary push to `main` with no environment set. There's no
schedule-specific subject shape. Without this second entry, `drift.yml` would authenticate as
`pull_request` for PR-triggered test jobs but have no valid subject at all for its own scheduled
runs — confirmed by hitting exactly that gap when `drift.yml` was first added, before this line
existed.

`ReadOnlyAccess` covers everything `terraform plan` and `terraform test` (plan-mode) need, with one
narrow, deliberate exception: `drift.yml` also needs to publish one SNS message per environment
when it finds drift, and `ReadOnlyAccess` excludes `sns:Publish` entirely. Rather than reach for
the write-capable role just for that, `terraform_plan` gets a single additional statement scoped to
exactly the two alert topics the observability module creates:

```hcl
resource "aws_iam_role_policy" "terraform_plan_sns_publish" {
  name = "sns-publish-alerts"
  role = aws_iam_role.terraform_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = [
        "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dev-cloudforge-alerts",
        "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:prod-cloudforge-alerts",
      ]
    }]
  })
}
```

The role that can assume `terraform_plan` never gains write access anywhere else; the role that can
publish an alert never gains read-only access to the rest of the account beyond what it already
had. One narrow addition, not an escalation.

**`terraform_apply`** — read-write (`PowerUserAccess`), assumed only by push-triggered jobs on
`main`: `terraform apply` for both dev and prod, and `app.yml`'s deploy steps (S3 upload, launch
template version, instance refresh, ALB weight shift).

```hcl
"token.actions.githubusercontent.com:sub" = [
  "${var.github_oidc_subject_prefix}:ref:refs/heads/${var.default_branch}",
  "${var.github_oidc_subject_prefix}:environment:dev",
  "${var.github_oidc_subject_prefix}:environment:prod",
]
```

Same underlying mechanic as the schedule case above, from the other direction: a job with no
`environment:` key gets a ref-based subject; a job that sets `environment: dev` or
`environment: prod` (as `apply-dev`/`apply-prod` both do, so each shows up under GitHub's
environment-scoped deployment history) gets an environment-based subject *instead* — GitHub issues
exactly one shape per job, never both. A trust policy written for only one shape would correctly
authenticate some push-triggered jobs in this same workflow and silently reject others, depending
on whether that specific job happens to declare an environment. All three subjects have to be
listed for one role to cover every push-triggered job in the pipeline.

`PowerUserAccess` deliberately excludes IAM administration — full admin would let a compromised
apply step create or modify any IAM principal in the account, including its own role. But every
module in this project provisions its own IAM roles (one per EC2 instance profile, roughly), so
`terraform apply` needs *some* IAM permissions or it fails the moment it touches one. The fix is a
second scoped statement, not a broader managed policy:

```hcl
Resource = [
  "arn:aws:iam::*:role/dev-*",
  "arn:aws:iam::*:role/prod-*",
  "arn:aws:iam::*:role/test-*",
  "arn:aws:iam::*:instance-profile/dev-*",
  "arn:aws:iam::*:instance-profile/prod-*",
  "arn:aws:iam::*:instance-profile/test-*",
]
```

CI can create, tag, and attach policies to any role or instance profile this project's own naming
convention produces — and nothing outside that prefix, including the human `cloudforge-admin` IAM
user used to bootstrap the account by hand.

## What this doesn't protect against

Worth being direct about the actual threat model here, not just the mechanism:

- This defends against **credential theft and long-lived secret sprawl** — there's no access key
  sitting in GitHub Secrets for an attacker to exfiltrate from a compromised Action, a misconfigured
  log, or a leaked `.env`. Every credential is minted per run and expires with it.
- It does **not** defend against a malicious commit that reaches `main` through the normal review
  process — that commit's workflow run legitimately gets `terraform_apply`'s full `PowerUserAccess`
  scope, same as any other push. The trust policy scopes *which workflows* can authenticate as
  which role; it has no opinion on what a workflow run authorized to be there is allowed to do to
  the account once it's in. Branch protection on `main` is the actual control for that risk, not
  this file.
- `PowerUserAccess` is broad by AWS's own definition (near-full access short of IAM/Organizations
  administration). It was chosen over hand-rolling a resource-level policy across every service
  this project touches (EC2, RDS, ElastiCache, S3, CloudFront, ElastiCache, ASG, CloudWatch, SNS,
  Secrets Manager, ...) because the maintenance cost of keeping a fully least-privileged policy in
  sync with a growing set of Terraform modules was judged higher than the risk it removes, for a
  single-operator portfolio project. A team account handling production traffic for others would
  reasonably make the opposite call.

## Alternatives considered

- **A single shared role for both plan and apply** — rejected. Would give unreviewed
  `pull_request` runs the same write access as a post-merge deploy.
- **Long-lived IAM user access keys as GitHub secrets** — rejected. The whole reason to prefer
  OIDC: nothing durable to rotate, leak, or forget to revoke when a workflow or repo is retired.
- **Scoping trust by repo name instead of the immutable owner/repo ID prefix** — rejected once
  GitHub's immutable-subject-claims change made the ID-based form the default; the name-based form
  is vulnerable to a rename/transfer silently repointing an old trust condition at a different
  repository.
