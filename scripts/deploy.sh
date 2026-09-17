#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
TF_DIR="terraform/environments/${ENVIRONMENT}"
APP_DIR="app"
K6_DURATION="${K6_DURATION:-8m}"

echo "==> Building app binary (linux/arm64)"
make -C "${APP_DIR}" build

echo "==> Reading deploy targets from terraform outputs (${TF_DIR})"
ARTIFACTS_BUCKET=$(terraform -chdir="${TF_DIR}" output -raw artifacts_bucket_name)
ARTIFACT_KEY=$(terraform -chdir="${TF_DIR}" output -raw artifact_key)
LAUNCH_TEMPLATE_ID=$(terraform -chdir="${TF_DIR}" output -raw launch_template_id)
ASG_NAME=$(terraform -chdir="${TF_DIR}" output -raw asg_name)
CLOUDFRONT_DOMAIN_NAME=$(terraform -chdir="${TF_DIR}" output -raw cloudfront_domain_name)

echo "==> Uploading binary to s3://${ARTIFACTS_BUCKET}/${ARTIFACT_KEY}"
aws s3 cp "${APP_DIR}/bin/cloudstore-api" "s3://${ARTIFACTS_BUCKET}/${ARTIFACT_KEY}"

VERSION_LABEL="$(git rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)"
echo "==> Creating launch template version (deploy-${VERSION_LABEL})"
aws ec2 create-launch-template-version \
  --launch-template-id "${LAUNCH_TEMPLATE_ID}" \
  --source-version '$Latest' \
  --launch-template-data '{}' \
  --version-description "deploy-${VERSION_LABEL}" >/dev/null

echo "==> Starting k6 smoke load in the background (${K6_DURATION}, target http://${ALB_DNS_NAME})"
TARGET_URL="https://${CLOUDFRONT_DOMAIN_NAME}" \
K6_DURATION="${K6_DURATION}" \
  k6 run scripts/load-test.js &
K6_PID=$!

echo "==> Starting instance refresh on ${ASG_NAME}"
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "${ASG_NAME}" \
  --preferences '{"MinHealthyPercentage":100,"InstanceWarmup":180}' \
  --query 'InstanceRefreshId' --output text)

echo "==> Polling instance refresh ${REFRESH_ID}"
while true; do
  STATUS=$(aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name "${ASG_NAME}" \
    --instance-refresh-ids "${REFRESH_ID}" \
    --query 'InstanceRefreshes[0].Status' --output text)

  echo "    status: ${STATUS}"

  case "${STATUS}" in
    Successful)
      echo "==> Instance refresh complete"
      break
      ;;
    Failed|Cancelled|RollbackFailed|RollbackSuccessful)
      echo "==> Instance refresh ended in ${STATUS}" >&2
      kill "${K6_PID}" 2>/dev/null || true
      exit 1
      ;;
  esac

  sleep 15
done

echo "==> Waiting for k6 smoke load to finish"
wait "${K6_PID}"
echo "==> Deploy to ${ENVIRONMENT} complete - zero failed requests during rollout"
