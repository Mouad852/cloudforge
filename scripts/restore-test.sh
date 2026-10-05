#!/usr/bin/env bash
set -euo pipefail

# Runs CloudForge's manual, point-in-time RDS restore drill (PLAN.md M11.3 / E5).
# It creates one marker in the live database, waits until RDS can restore past
# that marker, restores a temporary instance, verifies the marker and source
# table count through SSM, then deletes the temporary instance. The timeline
# is deliberately written outside the repository so an experiment result is
# reviewed before any measured number is committed.

usage() {
  cat <<'EOF'
Usage: scripts/restore-test.sh <dev|prod> [options]

Options:
  --out <dir>              Write the drill timeline here (must be outside a git worktree).
  --max-wait-seconds <n>   Wait at most n seconds for RDS and SSM steps (default: 1800).
  --yes                    Run without the final interactive confirmation.

The drill writes a small marker row to the live database, then creates and
deletes a temporary RDS instance. It does not change Terraform state or the
source DB instance. The timeline records every instance-class/storage-type/AZ capacity
attempt; do not report an RTO until a run completes successfully.
EOF
  exit 2
}

die() { echo "ERROR: $*" >&2; exit 1; }
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

[[ $# -ge 1 ]] || usage
ENVIRONMENT="$1"
shift
[[ "${ENVIRONMENT}" =~ ^(dev|prod)$ ]] || usage

OUT_DIR=""
MAX_WAIT_SECONDS=1800
ASSUME_YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --max-wait-seconds) MAX_WAIT_SECONDS="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[[ "${MAX_WAIT_SECONDS}" =~ ^[0-9]+$ && "${MAX_WAIT_SECONDS}" -ge 60 ]] || \
  die "--max-wait-seconds must be an integer of at least 60"
command -v aws >/dev/null || die "the AWS CLI is required"
command -v base64 >/dev/null || die "base64 is required"
command -v date >/dev/null || die "date is required"

REGION="eu-west-3"
SOURCE_DB="${ENVIRONMENT}-cloudforge-db"
ASG_NAME="${ENVIRONMENT}-cloudforge-app"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
MARKER="restore-drill-${RUN_ID}"
TARGET_DB="${ENVIRONMENT}-cf-restore-${RUN_ID}"
TARGET_DB="${TARGET_DB:0:63}"

OUT_DIR="${OUT_DIR:-${HOME}/cloudforge-restore-drills/${ENVIRONMENT}-${RUN_ID}}"
mkdir -p "${OUT_DIR}"
if git -C "${OUT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rmdir "${OUT_DIR}" 2>/dev/null || true
  die "${OUT_DIR} is inside a git working tree; choose an output directory outside the repository"
fi
OUT_DIR=$(cd "${OUT_DIR}" && pwd)
TIMELINE="${OUT_DIR}/timeline.log"

log() {
  local line
  line="$(ts) $*"
  echo "${line}"
  echo "${line}" >>"${TIMELINE}"
}

rds() { aws rds --region "${REGION}" "$@"; }
ssm() { aws ssm --region "${REGION}" "$@"; }

deadline_epoch() { echo $(( $(date -u +%s) + MAX_WAIT_SECONDS )); }
within_deadline() { [[ $(date -u +%s) -lt "$1" ]]; }

require_value() {
  local name="$1" value="$2"
  [[ -n "${value}" && "${value}" != "None" && "${value}" != "null" ]] || \
    die "could not read ${name} from ${SOURCE_DB}; is ${ENVIRONMENT} running in ${REGION}?"
}

TARGET_CREATED=false
MARKER_WRITTEN=false
CLEANED=false
cleanup() {
  local rc=$?
  [[ "${CLEANED}" == true ]] && return
  CLEANED=true
  set +e
  if [[ "${TARGET_CREATED}" == true ]]; then
    log "cleanup: deleting temporary DB ${TARGET_DB} without a final snapshot"
    rds delete-db-instance --db-instance-identifier "${TARGET_DB}" \
      --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1
    local deadline
    deadline=$(deadline_epoch)
    while within_deadline "${deadline}"; do
      if ! rds describe-db-instances --db-instance-identifier "${TARGET_DB}" >/dev/null 2>&1; then
        log "cleanup: ${TARGET_DB} deleted"
        break
      fi
      sleep 30
    done
    if rds describe-db-instances --db-instance-identifier "${TARGET_DB}" >/dev/null 2>&1; then
      log "WARNING: ${TARGET_DB} is still deleting; verify it is removed before treating this drill as complete"
    fi
  fi
  if [[ "${MARKER_WRITTEN}" == true ]]; then
    log "cleanup: removing source marker ${MARKER}"
    if ! run_ssm_script "remove source marker" "$(psql_script "${SOURCE_ENDPOINT}" "${SOURCE_SECRET}" "DELETE FROM restore_drill_markers WHERE marker = '${MARKER}';")" >/dev/null; then
      log "WARNING: could not remove source marker ${MARKER}; remove it manually after reviewing the SSM output"
    fi
  fi
  log "drill finished (exit code ${rc}); timeline: ${TIMELINE}"
  exit "${rc}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

log "restore drill prepared: source=${SOURCE_DB}, temporary target=${TARGET_DB}, marker=${MARKER}"
SOURCE_CLASS=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].DBInstanceClass' --output text)
SUBNET_GROUP=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].DBSubnetGroup.DBSubnetGroupName' --output text)
SECURITY_GROUPS=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].VpcSecurityGroups[].VpcSecurityGroupId' --output text)
PARAMETER_GROUP=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' --output text)
SOURCE_AZ=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].AvailabilityZone' --output text)
SOURCE_STORAGE=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].StorageType' --output text)
SOURCE_ENDPOINT=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].Endpoint.Address' --output text)
SOURCE_DATABASE=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].DBName' --output text)
SOURCE_SECRET=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
for field in SOURCE_CLASS SUBNET_GROUP SECURITY_GROUPS PARAMETER_GROUP SOURCE_AZ SOURCE_STORAGE SOURCE_ENDPOINT SOURCE_DATABASE SOURCE_SECRET; do
  require_value "${field}" "${!field}"
done

APP_INSTANCE=$(aws autoscaling describe-auto-scaling-groups --region "${REGION}" \
  --auto-scaling-group-names "${ASG_NAME}" \
  --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'].InstanceId | [0]" \
  --output text)
require_value "a healthy app instance" "${APP_INSTANCE}"

echo
echo "Environment:         ${ENVIRONMENT} (${REGION})"
echo "Source database:     ${SOURCE_DB}"
echo "Temporary database:  ${TARGET_DB}"
echo "App instance via SSM:${APP_INSTANCE}"
echo "Output:              ${OUT_DIR}"
echo "The source database receives one marker row; the temporary database is deleted afterwards."
if [[ "${ASSUME_YES}" != true ]]; then
  read -r -p "Start this restore drill? [y/N] " ANSWER
  [[ "${ANSWER}" =~ ^[yY]$ ]] || die "aborted; no marker or temporary database was created"
fi

run_ssm_script() {
  local label="$1" script="$2" command_id status deadline stdout stderr
  command_id=$(ssm send-command \
    --document-name AWS-RunShellScript \
    --instance-ids "${APP_INSTANCE}" \
    --comment "CloudForge restore drill: ${label}" \
    --parameters "commands=[\"echo ${script} | base64 -d | bash\"]" \
    --query 'Command.CommandId' --output text)
  require_value "SSM command id for ${label}" "${command_id}"
  deadline=$(deadline_epoch)
  while within_deadline "${deadline}"; do
    status=$(ssm get-command-invocation --command-id "${command_id}" --instance-id "${APP_INSTANCE}" \
      --query 'Status' --output text 2>/dev/null || true)
    case "${status}" in
      Success)
        stdout=$(ssm get-command-invocation --command-id "${command_id}" --instance-id "${APP_INSTANCE}" \
          --query 'StandardOutputContent' --output text)
        printf '%s\n' "${stdout}"
        return 0
        ;;
      Failed|Cancelled|TimedOut)
        stderr=$(ssm get-command-invocation --command-id "${command_id}" --instance-id "${APP_INSTANCE}" \
          --query 'StandardErrorContent' --output text 2>/dev/null || true)
        log "SSM ${label} failed with ${status}: ${stderr}"
        return 1
        ;;
    esac
    sleep 5
  done
  log "SSM ${label} timed out after ${MAX_WAIT_SECONDS}s (command ${command_id})"
  return 1
}

psql_script() {
  local endpoint="$1" secret_arn="$2" sql="$3"
  printf '%s' "$(cat <<EOF
set -euo pipefail
if ! command -v psql >/dev/null 2>&1; then
  dnf install -y postgresql15 || dnf install -y postgresql
fi
SECRET_JSON=\$(aws secretsmanager get-secret-value --region '${REGION}' --secret-id '${secret_arn}' --query SecretString --output text)
DB_USER=\$(printf '%s' "\${SECRET_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["username"])')
DB_PASSWORD=\$(printf '%s' "\${SECRET_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
export PGPASSWORD="\${DB_PASSWORD}"
export PGSSLMODE=require
psql --no-align --tuples-only --set=ON_ERROR_STOP=1 --host='${endpoint}' --username="\${DB_USER}" --dbname='${SOURCE_DATABASE}' <<'SQL'
${sql}
SQL
EOF
)" | base64 | tr -d '\n'
}

MARKER_SQL="CREATE TABLE IF NOT EXISTS restore_drill_markers (marker text PRIMARY KEY, written_at timestamptz NOT NULL); INSERT INTO restore_drill_markers (marker, written_at) VALUES ('${MARKER}', clock_timestamp()); SELECT 'MARKER_TIMESTAMP=' || to_char(written_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') FROM restore_drill_markers WHERE marker = '${MARKER}';"
MARKER_OUTPUT=$(run_ssm_script "write marker" "$(psql_script "${SOURCE_ENDPOINT}" "${SOURCE_SECRET}" "${MARKER_SQL}")") || die "could not write the source marker through SSM"
MARKER_WRITTEN=true
MARKER_TIME=$(printf '%s\n' "${MARKER_OUTPUT}" | sed -n 's/^MARKER_TIMESTAMP=//p' | tail -1)
require_value "marker timestamp" "${MARKER_TIME}"
MARKER_EPOCH=$(date -u -d "${MARKER_TIME}" +%s) || die "could not parse marker timestamp ${MARKER_TIME}"
log "marker written at ${MARKER_TIME}; waiting for LatestRestorableTime to include it"

LATEST_RESTORABLE=""
LATEST_EPOCH=0
deadline=$(deadline_epoch)
while within_deadline "${deadline}"; do
  LATEST_RESTORABLE=$(rds describe-db-instances --db-instance-identifier "${SOURCE_DB}" \
    --query 'DBInstances[0].LatestRestorableTime' --output text)
  if [[ -n "${LATEST_RESTORABLE}" && "${LATEST_RESTORABLE}" != "None" ]]; then
    LATEST_EPOCH=$(date -u -d "${LATEST_RESTORABLE}" +%s 2>/dev/null || echo 0)
    if [[ "${LATEST_EPOCH}" -ge "${MARKER_EPOCH}" ]]; then break; fi
  fi
  sleep 30
done
[[ "${LATEST_EPOCH}" -ge "${MARKER_EPOCH}" ]] || \
  die "LatestRestorableTime never reached marker ${MARKER_TIME}; no restore was started and no RPO is measured"
log "LatestRestorableTime ${LATEST_RESTORABLE} includes the marker"

# Try the live instance class and storage type/AZ first. Capacity errors then
# try the other gp volume type, each AZ in the DB subnet group, and finally the
# orderable db.t3.micro class. The timeline makes every fallback explicit; a
# successful fallback is not reported as if the first configuration had
# capacity.
SUBNET_AZS=$(rds describe-db-subnet-groups --db-subnet-group-name "${SUBNET_GROUP}" \
  --query 'DBSubnetGroups[0].Subnets[].SubnetAvailabilityZone.Name' --output text)
INSTANCE_CLASSES=()
for instance_class in "${SOURCE_CLASS}" db.t3.micro; do
  [[ " ${INSTANCE_CLASSES[*]} " == *" ${instance_class} "* ]] || INSTANCE_CLASSES+=("${instance_class}")
done
STORAGE_TYPES=()
for storage in "${SOURCE_STORAGE}" gp3 gp2; do
  [[ " ${STORAGE_TYPES[*]} " == *" ${storage} "* ]] || STORAGE_TYPES+=("${storage}")
done
AVAILABILITY_ZONES=()
for az in "${SOURCE_AZ}" ${SUBNET_AZS}; do
  [[ " ${AVAILABILITY_ZONES[*]} " == *" ${az} "* ]] || AVAILABILITY_ZONES+=("${az}")
done

RESTORE_STARTED_EPOCH=$(date -u +%s)
RESTORE_ACCEPTED=false
for instance_class in "${INSTANCE_CLASSES[@]}"; do
  for storage in "${STORAGE_TYPES[@]}"; do
    for az in "${AVAILABILITY_ZONES[@]}"; do
      log "restore attempt: class=${instance_class}, storage=${storage}, az=${az}"
      ATTEMPT_ERR="${OUT_DIR}/restore-${instance_class}-${storage}-${az}.err"
      if rds restore-db-instance-to-point-in-time \
        --source-db-instance-identifier "${SOURCE_DB}" \
        --target-db-instance-identifier "${TARGET_DB}" \
        --use-latest-restorable-time \
        --db-instance-class "${instance_class}" \
        --db-subnet-group-name "${SUBNET_GROUP}" \
        --vpc-security-group-ids ${SECURITY_GROUPS} \
        --db-parameter-group-name "${PARAMETER_GROUP}" \
        --availability-zone "${az}" \
        --storage-type "${storage}" \
        --no-multi-az --no-publicly-accessible \
        --tags "Key=Project,Value=cloudforge" "Key=Purpose,Value=restore-drill" \
        >"${OUT_DIR}/restore-${instance_class}-${storage}-${az}.json" 2>"${ATTEMPT_ERR}"; then
        TARGET_CREATED=true
        RESTORE_ACCEPTED=true
        log "restore request accepted: class=${instance_class}, storage=${storage}, az=${az}"
        break 3
      fi
      if grep -q 'InstanceQuotaExceeded' "${ATTEMPT_ERR}"; then
        log "RDS account quota blocked the temporary restore; free an instance slot (for example, make dev-down) and retry"
        log "restore request failed: $(tr '\n' ' ' <"${ATTEMPT_ERR}")"
        exit 1
      fi
      if grep -q 'InsufficientDBInstanceCapacity' "${ATTEMPT_ERR}"; then
        log "capacity unavailable: class=${instance_class}, storage=${storage}, az=${az}; trying documented fallback"
        continue
      fi
      log "restore request failed for a non-capacity reason: $(tr '\n' ' ' <"${ATTEMPT_ERR}")"
      exit 1
    done
  done
done
[[ "${RESTORE_ACCEPTED}" == true ]] || die "all instance-class/storage-type/AZ restore attempts lacked capacity; see ${OUT_DIR}"

log "waiting for temporary DB ${TARGET_DB} to become available"
deadline=$(deadline_epoch)
while within_deadline "${deadline}"; do
  TARGET_STATUS=$(rds describe-db-instances --db-instance-identifier "${TARGET_DB}" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)
  [[ "${TARGET_STATUS}" == "available" ]] && break
  sleep 30
done
[[ "${TARGET_STATUS:-}" == "available" ]] || die "temporary DB did not become available within ${MAX_WAIT_SECONDS}s"
TARGET_ENDPOINT=$(rds describe-db-instances --db-instance-identifier "${TARGET_DB}" --query 'DBInstances[0].Endpoint.Address' --output text)
require_value "temporary database endpoint" "${TARGET_ENDPOINT}"
TARGET_SECRET=$(rds describe-db-instances --db-instance-identifier "${TARGET_DB}" --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
require_value "temporary database master secret" "${TARGET_SECRET}"
RESTORE_AVAILABLE_EPOCH=$(date -u +%s)
log "temporary DB available after $((RESTORE_AVAILABLE_EPOCH - RESTORE_STARTED_EPOCH))s"

VERIFY_SQL="SELECT 'MARKER_FOUND=' || count(*) FROM restore_drill_markers WHERE marker = '${MARKER}'; SELECT 'PRODUCT_ROW_COUNT=' || count(*) FROM products;"
VERIFY_OUTPUT=$(run_ssm_script "verify restored marker" "$(psql_script "${TARGET_ENDPOINT}" "${TARGET_SECRET}" "${VERIFY_SQL}")") || die "could not query the temporary database through SSM"
printf '%s\n' "${VERIFY_OUTPUT}" | tee "${OUT_DIR}/verification.log"
MARKER_FOUND=$(printf '%s\n' "${VERIFY_OUTPUT}" | sed -n 's/^MARKER_FOUND=//p' | tail -1)
PRODUCT_ROW_COUNT=$(printf '%s\n' "${VERIFY_OUTPUT}" | sed -n 's/^PRODUCT_ROW_COUNT=//p' | tail -1)
[[ "${MARKER_FOUND}" == "1" ]] || die "marker ${MARKER} was not found in the temporary database"
require_value "restored products row count" "${PRODUCT_ROW_COUNT}"

RPO_SECONDS=$((LATEST_EPOCH - MARKER_EPOCH))
log "SUCCESS: marker verified; products=${PRODUCT_ROW_COUNT}; RPO observed=${RPO_SECONDS}s; restore-ready time=$((RESTORE_AVAILABLE_EPOCH - RESTORE_STARTED_EPOCH))s"
echo "Record the timeline's actual values in docs/experiments/05-database-restore.md only after reviewing this run."
