#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
if [[ -z "$ENVIRONMENT" ]]; then
  echo "usage: $0 <environment>" >&2
  exit 2
fi

case "$ENVIRONMENT" in
  prod|dev) ;;
  *)
    echo "unsupported environment: $ENVIRONMENT" >&2
    exit 2
    ;;
esac

REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-eu-west-3}}"
SECRET_NAME="cloudforge/${ENVIRONMENT}/redis-auth"
TF_DIR="terraform/environments/${ENVIRONMENT}"
TF_ADDRESS="module.cache.aws_secretsmanager_secret.redis_auth"

# State inspection/import needs the same provider set as the following apply.
# Initialising here makes the lifecycle target work from a clean checkout too.
terraform -chdir="$TF_DIR" init -input=false -upgrade=false -lockfile=readonly >/dev/null

# A destroyed environment may leave the named secret in Secrets Manager's
# recovery window. Restore it before Terraform tries to create the same name.
if aws secretsmanager describe-secret \
  --region "$REGION" \
  --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  DELETED_DATE="$(aws secretsmanager describe-secret \
    --region "$REGION" \
    --secret-id "$SECRET_NAME" \
    --query DeletedDate \
    --output text)"

  if [[ -n "$DELETED_DATE" && "$DELETED_DATE" != "None" && "$DELETED_DATE" != "null" ]]; then
    echo "==> restoring scheduled-for-deletion secret: $SECRET_NAME"
    aws secretsmanager restore-secret \
      --region "$REGION" \
      --secret-id "$SECRET_NAME" >/dev/null
  fi

  # prod-down destroys the Terraform resource from state. Import the restored
  # secret so Terraform manages the existing object instead of attempting a
  # duplicate CreateSecret call.
  if ! terraform -chdir="$TF_DIR" state list 2>/dev/null | grep -Fxq "$TF_ADDRESS"; then
    echo "==> importing existing Redis secret into Terraform state"
    terraform -chdir="$TF_DIR" import "$TF_ADDRESS" "$SECRET_NAME"
  fi
else
  echo "==> no existing $SECRET_NAME secret; Terraform will create it"
fi
