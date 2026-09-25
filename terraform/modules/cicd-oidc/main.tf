data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# AWS validates the token against GitHub's published signing keys, not this
# thumbprint - GitHub's OIDC cert chain has used a publicly-trusted CA since
# 2023 and AWS stopped checking it. The provider resource still requires a
# value, so it's fetched live rather than hardcoded, so it can't go stale if
# GitHub ever rotates the certificate.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

# Read-only - assumed by pull_request-triggered runs (terraform.yml posts a
# `plan` as a PR comment without granting write access to an unreviewed
# branch) and by drift.yml's schedule/workflow_dispatch-triggered runs. A
# schedule-triggered workflow always executes against the default branch and
# gets the same ref-based subject as a plain push to main with no
# `environment:` set - GitHub doesn't issue a schedule-specific subject
# shape - so that subject is listed here too, alongside :pull_request.
resource "aws_iam_role" "terraform_plan" {
  name = "cloudforge-github-actions-terraform-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "${var.github_oidc_subject_prefix}:pull_request",
            "${var.github_oidc_subject_prefix}:ref:refs/heads/${var.default_branch}",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess deliberately excludes sns:Publish. drift.yml (assumes this
# role) needs to push one alert per environment when `terraform plan
# -detailed-exitcode` finds drift, so this grants exactly that one action,
# scoped to only the two alerts topics the observability module creates -
# never the apply role, never a wildcard resource.
resource "aws_iam_role_policy" "terraform_plan_sns_publish" {
  name = "sns-publish-alerts"
  role = aws_iam_role.terraform_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sns:Publish"
      Resource = [
        "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dev-cloudforge-alerts",
        "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:prod-cloudforge-alerts",
      ]
    }]
  })
}

# ReadOnlyAccess also excludes secretsmanager:GetSecretValue, and every plan
# refreshes the cache module's aws_secretsmanager_secret_version, which reads
# the value back - without this, every PR plan and every drift check fails.
# It exposes nothing new: the same token is in the Terraform state, which
# ReadOnlyAccess can already read. Scoped to exactly the two Redis AUTH
# secrets; "??????" matches only the 6-character suffix AWS appends to a
# secret's name, so no other secret under cloudforge/ can match.
resource "aws_iam_role_policy" "terraform_plan_read_redis_auth" {
  name = "read-redis-auth-secrets"
  role = aws_iam_role.terraform_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:cloudforge/dev/redis-auth-??????",
        "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:cloudforge/prod/redis-auth-??????",
      ]
    }]
  })
}

# Read-write - assumed only by workflow runs on pushes to the default branch,
# for both `terraform apply` (dev/prod) and app.yml's deploy steps (S3
# upload, launch template version, ASG instance refresh, ALB weight shift).
resource "aws_iam_role" "terraform_apply" {
  name = "cloudforge-github-actions-terraform-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # A job with no `environment:` gets a ref-based subject; a job that
          # sets `environment: dev`/`environment: prod` (as apply-dev/
          # apply-prod both do) gets an environment-based subject instead -
          # GitHub issues one shape or the other, never both, so both must be
          # listed here for the same role to cover every push-triggered job.
          "token.actions.githubusercontent.com:sub" = [
            "${var.github_oidc_subject_prefix}:ref:refs/heads/${var.default_branch}",
            "${var.github_oidc_subject_prefix}:environment:dev",
            "${var.github_oidc_subject_prefix}:environment:prod",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# PowerUserAccess deliberately excludes IAM administration, and every module
# in this project creates its own IAM roles. Without this, `terraform apply`
# would fail the moment it touched any of them. Scoped to the dev-*/prod-*
# naming convention every module already follows, so CI can manage
# project-created roles but never the human cloudforge-admin IAM user or
# anything outside that prefix.
resource "aws_iam_role_policy" "terraform_apply_iam_scoped" {
  name = "iam-for-project-roles"
  role = aws_iam_role.terraform_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:ListInstanceProfilesForRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:PassRole",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
      ]
      Resource = [
        "arn:aws:iam::*:role/dev-*",
        "arn:aws:iam::*:role/prod-*",
        "arn:aws:iam::*:role/test-*",
        "arn:aws:iam::*:instance-profile/dev-*",
        "arn:aws:iam::*:instance-profile/prod-*",
        "arn:aws:iam::*:instance-profile/test-*",
      ]
    }]
  })
}
