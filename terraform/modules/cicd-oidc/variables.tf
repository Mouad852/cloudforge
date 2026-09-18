variable "github_oidc_subject_prefix" {
  description = "The literal \"repo:...\" prefix GitHub's OIDC tokens carry for this repository. Since GitHub enabled immutable subject claims (`use_immutable_subject`), this is no longer just \"repo:$${github_repository}\" - it includes GitHub's numeric owner/repo IDs, e.g. \"repo:owner@12345/name@67890\". Get the exact value with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (the `sub_claim_prefix` field) - it will not change unless the repo is renamed/transferred, in which case GitHub reissues a new prefix and this must be updated to match."
  type        = string

  validation {
    condition     = startswith(var.github_oidc_subject_prefix, "repo:")
    error_message = "github_oidc_subject_prefix must start with \"repo:\" (GitHub's OIDC subject prefix, e.g. \"repo:owner@12345/name@67890\"). A wrong prefix makes the CI roles impossible to assume, and the failure only shows up inside a workflow run."
  }
}

variable "default_branch" {
  description = "Branch allowed to assume the terraform-apply / app-deploy role - the plan role is open to any pull_request against this repo"
  type        = string
  default     = "main"
}
