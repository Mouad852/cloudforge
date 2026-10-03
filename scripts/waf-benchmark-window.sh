#!/usr/bin/env bash
set -euo pipefail

# Runs a load test with THIS machine's public IPv4 exempted from the WAF's
# per-IP rate limit, for exactly as long as the test runs (PLAN.md §9, D2;
# docs/runbooks/load-test-window.md). Run it on the load generator itself.
#
# What it guarantees:
#   - the exemption list (<env>-cloudforge-rate-limit-exempt) is empty before
#     it starts, holds exactly one /32 during the run, and is emptied and
#     verified empty afterwards - on success, failure, Ctrl-C, SIGTERM or a
#     dropped session (EXIT/INT/TERM/HUP traps);
#   - the list is referenced exactly once in the web ACL, inside the
#     RateLimitPerIP rule's scope-down, so it can only exempt from rate
#     limiting: every managed rule still inspects the benchmark traffic;
#   - the web ACL itself is unchanged by the window (same lock token before
#     and after), so the 2,000/5 min limit stayed in force for everyone else.
#
# What it cannot guarantee: cleanup if the machine itself dies (SIGKILL, power,
# a terminated host). The backstops are the daily drift check, which fails
# and opens an issue if the list is not empty, and `--cleanup-only`.
#
# The address is never written to the timeline: only a short hash of it, so
# the timeline can be pasted into an experiment report. Output goes outside
# the repository by default, and the script refuses a path inside a git
# working tree.

usage() {
  cat <<'EOF'
Usage:
  scripts/waf-benchmark-window.sh <dev|prod> [options] [-- benchmark command...]
  scripts/waf-benchmark-window.sh <dev|prod> --cleanup-only

Options:
  --ip <IPv4>          Public IPv4 of the load generator. Default: detected
                       with https://checkip.amazonaws.com from this machine.
  --max-minutes <n>    Hard cap on the benchmark's run time (default 30).
  --settle-seconds <n> Wait after adding the exemption, for WAF propagation
                       (default 60).
  --out <dir>          Output directory, outside any git repository
                       (default ~/cloudforge-benchmarks/<env>-<UTC time>).
  --yes                Do not ask for confirmation.
  --cleanup-only       Empty the exemption list, verify it, and exit. The
                       manual fallback after an interrupted window.

The benchmark gets TARGET_URL=http://<this environment's ALB> in its
environment. Without a command after `--`, it runs
  k6 run scripts/capacity-test.js
with a summary export and per-request CSV written to the output directory.
EOF
  exit 2
}

die() { echo "ERROR: $*" >&2; exit 1; }
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

TIMELINE=""
log() {
  local line
  line="$(ts) $*"
  echo "${line}"
  if [[ -n "${TIMELINE}" ]]; then echo "${line}" >>"${TIMELINE}"; fi
}

[[ $# -ge 1 ]] || usage
ENVIRONMENT="$1"
shift
[[ "${ENVIRONMENT}" =~ ^(dev|prod)$ ]] || usage

IP=""
MAX_MINUTES=30
SETTLE_SECONDS=60
OUT_DIR=""
ASSUME_YES=false
CLEANUP_ONLY=false
BENCH_CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) IP="${2:-}"; shift 2 ;;
    --max-minutes) MAX_MINUTES="${2:-}"; shift 2 ;;
    --settle-seconds) SETTLE_SECONDS="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    --cleanup-only) CLEANUP_ONLY=true; shift ;;
    --) shift; BENCH_CMD=("$@"); break ;;
    -h | --help) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[[ "${MAX_MINUTES}" =~ ^[0-9]+$ && "${MAX_MINUTES}" -ge 1 ]] || die "--max-minutes must be a positive integer"
[[ "${SETTLE_SECONDS}" =~ ^[0-9]+$ ]] || die "--settle-seconds must be a non-negative integer"

# Every call names the region: on the operator's machine AWS_DEFAULT_REGION
# vanishes with each new terminal, and a wrong region makes the list look
# missing instead of failing loudly.
REGION="eu-west-3"
IPSET_NAME="${ENVIRONMENT}-cloudforge-rate-limit-exempt"
ACL_NAME="${ENVIRONMENT}-cloudforge-alb-waf"
ALB_NAME="${ENVIRONMENT}-cloudforge-alb"
RATE_RULE="RateLimitPerIP"

command -v aws >/dev/null || die "the AWS CLI is required"

waf() { aws wafv2 "$@" --scope REGIONAL --region "${REGION}"; }

IPSET_ID=$(waf list-ip-sets --query "IPSets[?Name=='${IPSET_NAME}'].Id | [0]" --output text)
[[ -n "${IPSET_ID}" && "${IPSET_ID}" != "None" ]] || die "IP set ${IPSET_NAME} not found in ${REGION} - is ${ENVIRONMENT} up, with the D2 change applied?"
IPSET_ARN=$(waf list-ip-sets --query "IPSets[?Name=='${IPSET_NAME}'].ARN | [0]" --output text)

ipset_addresses() {
  waf get-ip-set --name "${IPSET_NAME}" --id "${IPSET_ID}" --query "IPSet.Addresses" --output text
}

ipset_count() {
  waf get-ip-set --name "${IPSET_NAME}" --id "${IPSET_ID}" --query "length(IPSet.Addresses)" --output text
}

# UpdateIPSet replaces the whole object: an omitted description would be
# cleared (and show up as drift), so the current one is sent back unchanged.
# The full request goes through --cli-input-json because that is the one
# reliable way to send an empty address list.
set_addresses() {
  local addresses_json="$1" token description attempt
  for attempt in 1 2 3 4 5; do
    token=$(waf get-ip-set --name "${IPSET_NAME}" --id "${IPSET_ID}" --query "LockToken" --output text) || true
    description=$(waf get-ip-set --name "${IPSET_NAME}" --id "${IPSET_ID}" --query "IPSet.Description" --output text) || true
    [[ "${description}" == "None" ]] && description=""
    description=${description//\\/\\\\}
    description=${description//\"/\\\"}
    if aws wafv2 update-ip-set --region "${REGION}" --cli-input-json \
      "{\"Name\":\"${IPSET_NAME}\",\"Scope\":\"REGIONAL\",\"Id\":\"${IPSET_ID}\",\"Description\":\"${description}\",\"Addresses\":${addresses_json},\"LockToken\":\"${token}\"}" \
      >/dev/null; then
      return 0
    fi
    echo "update-ip-set failed (attempt ${attempt}/5), retrying with a fresh lock token" >&2
    sleep 3
  done
  return 1
}

manual_fallback() {
  cat >&2 <<EOF

!!! The rate-limit exemption may still be active. Empty it now, from any
!!! machine with AWS credentials:

    scripts/waf-benchmark-window.sh ${ENVIRONMENT} --cleanup-only

!!! or in the console: WAF & Shield > IP sets (region ${REGION}) >
!!! ${IPSET_NAME} > select every address > Delete. Then confirm the list is
!!! empty. Do not screenshot the list while it holds an address.
EOF
}

if [[ "${CLEANUP_ONLY}" == true ]]; then
  log "cleanup-only: emptying ${IPSET_NAME} (it holds $(ipset_count) address(es))"
  set_addresses "[]" || { manual_fallback; exit 3; }
  [[ "$(ipset_count)" == "0" ]] || { manual_fallback; exit 3; }
  log "cleanup-only: ${IPSET_NAME} verified empty"
  exit 0
fi

# ---- preflight, before anything is changed ----------------------------------

command -v timeout >/dev/null || die "GNU timeout is required (coreutils; 'gtimeout' on macOS is not supported)"

hash_ref() {
  if command -v sha256sum >/dev/null; then
    printf '%s' "$1" | sha256sum | cut -c1-12
  else
    printf '%s' "$1" | shasum -a 256 | cut -c1-12
  fi
}

is_public_ipv4() {
  local ip="$1" o
  [[ "${ip}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
  for o in "${BASH_REMATCH[@]:1}"; do
    [[ $((10#${o})) -le 255 ]] || return 1
  done
  a=$((10#${a}))
  b=$((10#${b}))
  ((a == 0 || a == 10 || a == 127 || a >= 224)) && return 1
  ((a == 100 && b >= 64 && b <= 127)) && return 1
  ((a == 169 && b == 254)) && return 1
  ((a == 172 && b >= 16 && b <= 31)) && return 1
  ((a == 192 && b == 168)) && return 1
  return 0
}

DETECTED_IP=$(curl -fsS --max-time 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)
if [[ -z "${IP}" ]]; then
  IP="${DETECTED_IP}"
  [[ -n "${IP}" ]] || die "could not detect this machine's public IPv4 - pass --ip"
elif [[ -n "${DETECTED_IP}" && "${DETECTED_IP}" != "${IP}" ]]; then
  echo "WARNING: --ip differs from this machine's detected egress address." >&2
  echo "         Run this script on the load generator, or the benchmark will hit the rate limit." >&2
fi
is_public_ipv4 "${IP}" || die "not a public IPv4 address: the WAF only ever sees the generator's public egress address"
IP_REF=$(hash_ref "${IP}")

[[ "$(ipset_count)" == "0" ]] || die "${IPSET_NAME} is not empty. Another window may be running, or one was interrupted. Investigate, then run with --cleanup-only."

ACL_ID=$(waf list-web-acls --query "WebACLs[?Name=='${ACL_NAME}'].Id | [0]" --output text)
[[ -n "${ACL_ID}" && "${ACL_ID}" != "None" ]] || die "web ACL ${ACL_NAME} not found"
acl() { waf get-web-acl --name "${ACL_NAME}" --id "${ACL_ID}" "$@"; }

REFS=$( (acl --output json | grep -oF "${IPSET_ARN}" || true) | wc -l | tr -d '[:space:]')
[[ "${REFS}" == "1" ]] || die "the exemption list is referenced ${REFS} times in ${ACL_NAME}, expected exactly 1 (the rate rule's scope-down)"
SCOPED=$(acl --query "WebACL.Rules[?Name=='${RATE_RULE}'] | [0].Statement.RateBasedStatement.ScopeDownStatement.NotStatement.Statement.IPSetReferenceStatement.ARN" --output text)
[[ "${SCOPED}" == "${IPSET_ARN}" ]] || die "the exemption list is not the NOT scope-down of ${RATE_RULE} - refusing to use it"
RATE_LIMIT=$(acl --query "WebACL.Rules[?Name=='${RATE_RULE}'] | [0].Statement.RateBasedStatement.Limit" --output text)
ACL_TOKEN_BEFORE=$(acl --query "LockToken" --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers --names "${ALB_NAME}" --region "${REGION}" --query "LoadBalancers[0].DNSName" --output text)
export TARGET_URL="http://${ALB_DNS}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT_DIR="${OUT_DIR:-${HOME}/cloudforge-benchmarks/${ENVIRONMENT}-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${OUT_DIR}"
if git -C "${OUT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rmdir "${OUT_DIR}" 2>/dev/null || true
  die "${OUT_DIR} is inside a git working tree - its logs must never be committed, choose a path outside the repository"
fi
OUT_DIR=$(cd "${OUT_DIR}" && pwd)
TIMELINE="${OUT_DIR}/timeline.log"

if [[ ${#BENCH_CMD[@]} -eq 0 ]]; then
  command -v k6 >/dev/null || die "k6 is required for the default benchmark (or pass a command after --)"
  BENCH_CMD=(k6 run --summary-export "${OUT_DIR}/k6-summary.json" --out "csv=${OUT_DIR}/k6-metrics.csv" "${SCRIPT_DIR}/capacity-test.js")
fi

# A CI plan or apply during the window refreshes this list. Plans are posted
# to public issues and PR comments, and an apply writes the list into the
# versioned state bucket. The drift check runs at 06:00 UTC and the dev
# nightly destroy at 23:00 UTC.
HOUR=$((10#$(date -u +%H)))
if ((HOUR == 5 || HOUR == 6 || HOUR == 22 || HOUR == 23)); then
  echo "WARNING: $(date -u +%H:%M) UTC is close to a scheduled CI run (drift 06:00, nightly destroy 23:00)." >&2
  echo "         Prefer another time: nothing in CI should plan or apply while the list holds an address." >&2
fi

echo
echo "Environment:       ${ENVIRONMENT}"
echo "Exempted source:   one /32 (ref ${IP_REF}), from the ${RATE_RULE} rule only"
echo "Rate limit:        ${RATE_LIMIT} requests / 5 min / IP for everyone else (unchanged)"
echo "Benchmark:         ${BENCH_CMD[*]}"
echo "Hard time cap:     ${MAX_MINUTES} min"
echo "Output:            ${OUT_DIR}"
echo "No terraform plan/apply, in CI or locally, until this window ends."
if [[ "${ASSUME_YES}" != true ]]; then
  read -r -p "Open the window? [y/N] " ANSWER
  [[ "${ANSWER}" =~ ^[yY]$ ]] || die "aborted, nothing changed"
fi

# ---- the window --------------------------------------------------------------

EXEMPTED=false
CLEANED=false
SAMPLER_PID=""

cleanup() {
  local rc=$?
  [[ "${CLEANED}" == true ]] && return
  CLEANED=true
  set +e
  if [[ -n "${SAMPLER_PID}" ]]; then kill "${SAMPLER_PID}" 2>/dev/null; fi

  local failed=false
  if [[ "${EXEMPTED}" == true ]]; then
    log "closing: removing the exemption"
    set_addresses "[]" || failed=true
    if [[ "$(ipset_count)" == "0" ]]; then
      log "exemption removed; ${IPSET_NAME} verified empty"
    else
      failed=true
      log "FAILED to verify ${IPSET_NAME} empty"
    fi
  fi

  local token_after
  token_after=$(acl --query "LockToken" --output text)
  if [[ "${token_after}" == "${ACL_TOKEN_BEFORE}" ]]; then
    log "web ACL ${ACL_NAME} unchanged during the window (same lock token); ${RATE_RULE} limit ${RATE_LIMIT}"
  else
    log "WARNING: web ACL ${ACL_NAME} changed during the window - check what changed before trusting this run"
  fi

  if [[ "${failed}" == true ]]; then
    manual_fallback
    exit 3
  fi
  log "window closed (exit code ${rc})"
  exit "${rc}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

log "window opened for ${ENVIRONMENT}: source ref ${IP_REF}, ${RATE_RULE} limit ${RATE_LIMIT} for everyone else"
EXEMPTED=true # set before the call, so an interrupt mid-update still cleans up
set_addresses "[\"${IP}/32\"]" || die "could not add the exemption"
CURRENT=$(ipset_addresses)
[[ "${CURRENT}" == "${IP}/32" ]] || die "after the update ${IPSET_NAME} does not hold exactly the expected /32"
log "exemption active: ${IPSET_NAME} holds exactly the expected /32"

if [[ "${SETTLE_SECONDS}" -gt 0 ]]; then
  log "waiting ${SETTLE_SECONDS}s for the WAF change to propagate"
  sleep "${SETTLE_SECONDS}"
fi

# The generator's own CPU, sampled every 5 s. If the generator saturates
# first, the benchmark measured the generator, not CloudForge.
if [[ -r /proc/stat ]]; then
  (
    read -r _ u n s i w x y z _ </proc/stat
    prev_idle=$((i + w))
    prev_total=$((u + n + s + i + w + x + y + z))
    while sleep 5; do
      read -r _ u n s i w x y z _ </proc/stat
      idle=$((i + w))
      total=$((u + n + s + i + w + x + y + z))
      dt=$((total - prev_total))
      di=$((idle - prev_idle))
      if ((dt > 0)); then echo "$(ts),$((100 * (dt - di) / dt))"; fi
      prev_idle=${idle}
      prev_total=${total}
    done
  ) >"${OUT_DIR}/generator-cpu.csv" &
  SAMPLER_PID=$!
fi

log "benchmark started"
set +e
# tee ignores SIGINT: a Ctrl-C must stop k6 gracefully (it still writes its
# summary), not kill the pipe k6 is writing into.
timeout --foreground --signal=INT --kill-after=60 "${MAX_MINUTES}m" "${BENCH_CMD[@]}" 2>&1 |
  (trap '' INT && exec tee "${OUT_DIR}/benchmark.log")
BENCH_RC=${PIPESTATUS[0]}
set -e
log "benchmark ended (exit code ${BENCH_RC}$([[ ${BENCH_RC} -eq 124 ]] && echo ", stopped by the ${MAX_MINUTES} min cap"))"

if [[ -s "${OUT_DIR}/generator-cpu.csv" ]]; then
  PEAK=$(cut -d, -f2 "${OUT_DIR}/generator-cpu.csv" | sort -n | tail -1)
  log "load generator CPU peak ${PEAK}%"
  if [[ "${PEAK}" -ge 85 ]]; then
    log "WARNING: the load generator ran at ${PEAK}% CPU - it may have been the bottleneck; do not report this run as CloudForge's capacity"
  fi
fi
if [[ -f "${OUT_DIR}/k6-summary.json" ]]; then
  DROPPED=$(tr -d '[:space:]' <"${OUT_DIR}/k6-summary.json" | grep -o '"dropped_iterations":{"count":[0-9.]*' | grep -o '[0-9.]*$' || true)
  if [[ -n "${DROPPED}" && "${DROPPED}" != "0" ]]; then
    log "WARNING: k6 dropped ${DROPPED} iterations - the generator could not sustain the requested arrival rate at some point"
  fi
fi

exit "${BENCH_RC}"
