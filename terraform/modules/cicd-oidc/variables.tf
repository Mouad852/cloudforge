variable "github_repository" {
  description = "GitHub repo this OIDC provider trusts, as \"owner/repo\" - only workflow runs from this exact repo can assume the roles below"
  type        = string
}

variable "default_branch" {
  description = "Branch allowed to assume the terraform-apply / app-deploy role - the plan role is open to any pull_request against this repo"
  type        = string
  default     = "main"
}
