#!/usr/bin/env bash
# Record an environment's expected lifecycle state after a successful, complete
# lifecycle operation. The drift workflow treats a torn-down environment as
# intentional only when this explicit GitHub variable says "down" *and* the
# Terraform state is empty; stale or missing state therefore fails safe.
set -euo pipefail

environment=${1:-}
state=${2:-}

case "$environment" in
  dev|prod) ;;
  *) echo "usage: $0 <dev|prod> <up|down>" >&2; exit 2 ;;
esac

case "$state" in
  up|down) ;;
  *) echo "usage: $0 <dev|prod> <up|down>" >&2; exit 2 ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required to record lifecycle state; leaving the prior state unchanged." >&2
  exit 1
fi

repository=${GITHUB_REPOSITORY:-}
if [ -z "$repository" ]; then
  remote=$(git config --get remote.origin.url 2>/dev/null || true)
  repository=${remote#git@github.com:}
  repository=${repository#https://github.com/}
  repository=${repository%.git}
fi

if [ -z "$repository" ] || [[ "$repository" != */* ]]; then
  echo "Could not determine the GitHub repository; leaving lifecycle state unchanged." >&2
  exit 1
fi

variable="CLOUDFORGE_${environment^^}_LIFECYCLE_STATE"
gh variable set "$variable" --repo "$repository" --body "$state"
echo "Recorded ${environment} lifecycle state as ${state} in ${variable}."
