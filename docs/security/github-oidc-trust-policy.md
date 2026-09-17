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
