provider "aws" {
  region = "eu-west-3"

  # Fake credentials and no validation calls: every data source below is
  # overridden, so nothing here ever talks to AWS.
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  github_oidc_subject_prefix = "repo:test-owner@111/test-repo@222"
}

# Plan-only, and fully offline: the three data sources (GitHub's TLS
# certificate, account ID, region) are overridden so the test never calls out
# to GitHub or AWS, and the OIDC provider's ARN is overridden because it is
# unknown until apply - without a value, jsonencode() makes every trust policy
# unknown and there would be nothing to assert on.
override_data {
  target = data.tls_certificate.github_actions
  values = {
    certificates = [{
      cert_pem             = "fixture"
      is_ca                = false
      issuer               = "fixture"
      not_after            = "2030-01-01T00:00:00Z"
      not_before           = "2020-01-01T00:00:00Z"
      public_key_algorithm = "RSA"
      serial_number        = "1"
      sha1_fingerprint     = "0000000000000000000000000000000000000000"
      signature_algorithm  = "SHA256-RSA"
      subject              = "fixture"
      version              = 3
    }]
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    name = "eu-west-3"
  }
}

override_resource {
  target          = aws_iam_openid_connect_provider.github_actions
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
}

run "plan_role_trusts_only_prs_and_the_default_branch" {
  command = plan

  assert {
    condition = toset(
      jsondecode(aws_iam_role.terraform_plan.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]
      ) == toset([
        "repo:test-owner@111/test-repo@222:pull_request",
        "repo:test-owner@111/test-repo@222:ref:refs/heads/main",
    ])
    error_message = "The read-only plan role must trust exactly pull_request runs and the default branch, nothing else"
  }

  assert {
    condition     = jsondecode(aws_iam_role.terraform_plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The plan role must require the sts.amazonaws.com audience"
  }

  assert {
    condition     = jsondecode(aws_iam_role.terraform_plan.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "The plan role must only be assumable through web identity federation"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.terraform_plan.policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "The plan role must stay read-only"
  }
}

run "apply_role_never_trusts_pull_requests" {
  command = plan

  assert {
    condition = toset(
      jsondecode(aws_iam_role.terraform_apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      ) == toset([
        "repo:test-owner@111/test-repo@222:ref:refs/heads/main",
        "repo:test-owner@111/test-repo@222:environment:dev",
        "repo:test-owner@111/test-repo@222:environment:prod",
    ])
    error_message = "The apply role must trust only the default branch and the dev/prod GitHub environments - never pull_request, which anyone can open"
  }

  assert {
    condition     = !can(jsondecode(aws_iam_role.terraform_apply.assume_role_policy).Statement[0].Condition.StringLike)
    error_message = "The apply role must match subjects exactly (StringEquals), never with wildcards (StringLike)"
  }

  assert {
    condition     = jsondecode(aws_iam_role.terraform_apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The apply role must require the sts.amazonaws.com audience"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.terraform_apply.policy_arn == "arn:aws:iam::aws:policy/PowerUserAccess"
    error_message = "The apply role's managed policy must be PowerUserAccess, which excludes IAM administration by design"
  }
}

run "oidc_provider_only_accepts_the_sts_audience" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.github_actions.url == "https://token.actions.githubusercontent.com" && toset(aws_iam_openid_connect_provider.github_actions.client_id_list) == toset(["sts.amazonaws.com"])
    error_message = "The OIDC provider must be GitHub's issuer with sts.amazonaws.com as the only client ID"
  }
}

run "plan_role_can_only_publish_to_the_two_alerts_topics" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.terraform_plan_sns_publish.policy).Statement[0].Action == "sns:Publish"
    error_message = "The plan role's extra policy must grant sns:Publish and nothing else"
  }

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.terraform_plan_sns_publish.policy).Statement[0].Resource) == toset([
      "arn:aws:sns:eu-west-3:123456789012:dev-cloudforge-alerts",
      "arn:aws:sns:eu-west-3:123456789012:prod-cloudforge-alerts",
    ])
    error_message = "sns:Publish must be scoped to exactly the dev and prod alerts topics, never a wildcard"
  }
}

run "apply_role_iam_access_is_limited_to_project_names" {
  command = plan

  assert {
    condition = alltrue([
      for r in jsondecode(aws_iam_role_policy.terraform_apply_iam_scoped.policy).Statement[0].Resource :
      can(regex("^arn:aws:iam::\\*:(role|instance-profile)/(dev|prod|test)-\\*$", r))
    ])
    error_message = "IAM permissions for CI must only cover roles and instance profiles named dev-*, prod-* or test-*, never the human admin user or anything else"
  }

  assert {
    condition = alltrue([
      for a in jsondecode(aws_iam_role_policy.terraform_apply_iam_scoped.policy).Statement[0].Action :
      !can(regex("\\*", a)) && !can(regex("^iam:(CreateUser|CreateAccessKey|CreateLoginProfile|AttachUserPolicy|PutUserPolicy)$", a))
    ])
    error_message = "CI's IAM actions must be an explicit list with no wildcards and no user or access-key management"
  }
}

run "default_branch_flows_into_both_trust_policies" {
  command = plan

  variables {
    default_branch = "release"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role.terraform_plan.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"], "repo:test-owner@111/test-repo@222:ref:refs/heads/release")
    error_message = "default_branch must reach the plan role's trust policy"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role.terraform_apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], "repo:test-owner@111/test-repo@222:ref:refs/heads/release")
    error_message = "default_branch must reach the apply role's trust policy"
  }
}

run "subject_prefix_without_repo_rejected" {
  command = plan

  variables {
    github_oidc_subject_prefix = "test-owner/test-repo"
  }

  expect_failures = [var.github_oidc_subject_prefix]
}
