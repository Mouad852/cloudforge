#!/usr/bin/env bash
set -euo pipefail

# Uploads the app binary only if the environment has none yet - the state
# right after an apply that built the environment from nothing (the nightly
# destroy, a DR rebuild). The instances wait for it at boot (user_data), so
# nothing else is needed to bring them up. An existing artifact is never
# replaced: shipping a new version is deploy.sh's job, with its instance
# refresh and k6 gate.

ENVIRONMENT="${1:-dev}"
TF_DIR="terraform/environments/${ENVIRONMENT}"
APP_DIR="app"

ARTIFACTS_BUCKET=$(terraform -chdir="${TF_DIR}" output -raw artifacts_bucket_name)
ARTIFACT_KEY=$(terraform -chdir="${TF_DIR}" output -raw artifact_key)

if HEAD_ERR=$(aws s3api head-object --bucket "${ARTIFACTS_BUCKET}" --key "${ARTIFACT_KEY}" 2>&1 >/dev/null); then
  echo "==> s3://${ARTIFACTS_BUCKET}/${ARTIFACT_KEY} already exists - leaving the deployed version alone"
  exit 0
fi

# Only a 404 means "missing". Anything else (expired credentials, a 403) is
# a real error, and uploading on top of it could replace a running version.
if [[ "${HEAD_ERR}" != *"(404)"* ]]; then
  echo "${HEAD_ERR}" >&2
  exit 1
fi

echo "==> No artifact in s3://${ARTIFACTS_BUCKET} yet - building and uploading"
make -C "${APP_DIR}" build
aws s3 cp "${APP_DIR}/bin/cloudstore-api" "s3://${ARTIFACTS_BUCKET}/${ARTIFACT_KEY}"
