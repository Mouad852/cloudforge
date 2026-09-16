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

# Read-only - assumed by any workflow run triggered by a pull_request against
# this repo, so terraform.yml can post a `plan` as a PR comment without
# granting write access to a branch nobody has reviewed yet.
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
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:pull_request"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
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
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.default_branch}"
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
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
      ]
      Resource = [
        "arn:aws:iam::*:role/dev-*",
        "arn:aws:iam::*:role/prod-*",
        "arn:aws:iam::*:instance-profile/dev-*",
        "arn:aws:iam::*:instance-profile/prod-*",
      ]
    }]
  })
}
