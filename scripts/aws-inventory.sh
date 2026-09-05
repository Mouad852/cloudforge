#!/usr/bin/env bash
# aws-inventory.sh — read-only sweep of every enabled region for billable resources.
#
# Creates nothing, deletes nothing, modifies nothing. Safe to run any time.
# Regions are scanned in parallel, so a full sweep takes ~30s rather than ~20min.
#
# Usage:  ./scripts/aws-inventory.sh [profile]        (default profile: cloudforge)
#
# This is the M0 "orphan-check" script. Run it after every teardown to confirm
# the account is actually back to $0.00/day.

set -uo pipefail

PROFILE="${1:-cloudforge}"
AWS="aws --profile $PROFILE --output text --no-cli-pager"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# aws --output text prints the literal string "None" for a null/empty result,
# and empty string for an empty list. Filter both, or every empty region
# reports a phantom resource.
clean() { tr '\t' '\n' | grep -vE '^(None|null)?$' || true; }

echo "AWS inventory sweep — profile: $PROFILE"
ACCT=$($AWS sts get-caller-identity --query Account 2>/dev/null | clean)
if [ -z "$ACCT" ]; then
  echo "ERROR: credentials not working for profile '$PROFILE'."
  echo "Run: aws configure --profile $PROFILE"
  exit 1
fi
echo "Account: $ACCT"

# ---------------------------------------------------------------- global scope
printf '\n\033[1m=== GLOBAL ===\033[0m\n'
G=0
for z in $($AWS route53 list-hosted-zones --query 'HostedZones[].Id' 2>/dev/null | clean); do
  printf '  \033[31m● Route53 hosted zone %s  ($0.50/mo)\033[0m\n' "$z"; G=$((G+1))
done
for d in $($AWS cloudfront list-distributions --query 'DistributionList.Items[].Id' 2>/dev/null | clean); do
  printf '  \033[31m● CloudFront distribution %s\033[0m\n' "$d"; G=$((G+1))
done
for b in $($AWS s3api list-buckets --query 'Buckets[].Name' 2>/dev/null | clean); do
  printf '  · S3 bucket %s\n' "$b"
done
for u in $($AWS iam list-users --query 'Users[].UserName' 2>/dev/null | clean); do
  printf '  · IAM user %s\n' "$u"
done
[ "$G" -eq 0 ] && echo "  (no billable global resources)"

# ---------------------------------------------------------------- per region
REGIONS=$($AWS ec2 describe-regions --query 'Regions[].RegionName' 2>/dev/null | clean | sort)
[ -z "$REGIONS" ] && { echo "ERROR: could not list regions"; exit 1; }

NREG=$(echo "$REGIONS" | wc -l | tr -d ' ')
printf '\nScanning %s regions in parallel' "$NREG"

scan_region() {
  local r="$1" out="$TMP/$1"
  local R="aws --profile $PROFILE --region $r --output text --no-cli-pager"
  : > "$out"
  em() { printf '  ● %s\n' "$1" >> "$out"; }

  # CloudFormation first — stacks usually OWN the resources below.
  for s in $($R cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE CREATE_FAILED DELETE_FAILED \
        --query 'StackSummaries[].StackName' 2>/dev/null | clean); do
    em "CloudFormation stack: $s   <-- DELETE THIS FIRST, it owns other resources"
  done
  for c in $($R eks list-clusters --query 'clusters[]' 2>/dev/null | clean); do
    em "EKS cluster: $c   (\$0.10/hr = \$73/mo, bills with zero workloads)"
  done
  for i in $($R ec2 describe-instances \
        --filters Name=instance-state-name,Values=running,stopped,stopping,pending \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' 2>/dev/null | clean | paste - - - 2>/dev/null); do
    em "EC2 instance: $i"
  done
  for n in $($R ec2 describe-nat-gateways --filter Name=state,Values=available,pending \
        --query 'NatGateways[].NatGatewayId' 2>/dev/null | clean); do
    em "NAT Gateway: $n   (\$0.045/hr = \$33/mo)"
  done
  for l in $($R elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' 2>/dev/null | clean); do
    em "Load balancer (v2): $l   (~\$18/mo)"
  done
  for l in $($R elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' 2>/dev/null | clean); do
    em "Load balancer (classic): $l"
  done
  for d in $($R rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' 2>/dev/null | clean); do
    em "RDS instance: $d"
  done
  for d in $($R rds describe-db-clusters --query 'DBClusters[].DBClusterIdentifier' 2>/dev/null | clean); do
    em "RDS cluster: $d"
  done
  for d in $($R rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' 2>/dev/null | clean); do
    em "RDS manual snapshot: $d   (storage charges)"
  done
  for e in $($R elasticache describe-cache-clusters --query 'CacheClusters[].CacheClusterId' 2>/dev/null | clean); do
    em "ElastiCache: $e"
  done
  for v in $($R ec2 describe-volumes --filters Name=status,Values=available \
        --query 'Volumes[].VolumeId' 2>/dev/null | clean); do
    em "Unattached EBS volume: $v   (billed while idle)"
  done
  for a in $($R ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].AllocationId' 2>/dev/null | clean); do
    em "Unassociated Elastic IP: $a   (\$0.005/hr when idle)"
  done
  for s in $($R ec2 describe-snapshots --owner-ids self --query 'Snapshots[].SnapshotId' 2>/dev/null | clean); do
    em "EBS snapshot: $s"
  done
  for i in $($R ec2 describe-images --owners self --query 'Images[].ImageId' 2>/dev/null | clean); do
    em "AMI: $i   (backing snapshot bills)"
  done
  for k in $($R kms list-keys --query 'Keys[].KeyId' 2>/dev/null | clean); do
    local META
    META=$($R kms describe-key --key-id "$k" --query 'KeyMetadata.[KeyManager,KeyState]' 2>/dev/null | tr '\t' '/')
    case "$META" in
      CUSTOMER/Enabled)         em "KMS customer key: $k   (\$1/mo)";;
      CUSTOMER/PendingDeletion) em "KMS key pending deletion: $k   (\$1/mo until the 7-day window ends — expected)";;
    esac
  done
  for s in $($R secretsmanager list-secrets --query 'SecretList[].Name' 2>/dev/null | clean); do
    em "Secret: $s   (\$0.40/mo)"
  done
  for c in $($R ecs list-clusters --query 'clusterArns[]' 2>/dev/null | clean); do
    em "ECS cluster: $(basename "$c")"
  done
  for e in $($R ecr describe-repositories --query 'repositories[].repositoryName' 2>/dev/null | clean); do
    em "ECR repository: $e   (\$0.10/GB/mo)"
  done
  for f in $($R efs describe-file-systems --query 'FileSystems[].FileSystemId' 2>/dev/null | clean); do
    em "EFS file system: $f"
  done
  for v in $($R ec2 describe-vpcs --filters Name=isDefault,Values=false \
        --query 'Vpcs[].VpcId' 2>/dev/null | clean); do
    em "Non-default VPC: $v   (free itself — check what is inside)"
  done
  printf '.' >&2
}

export -f scan_region clean
export PROFILE TMP

for r in $REGIONS; do scan_region "$r" & done
wait
echo

# ---------------------------------------------------------------- report
FOUND=0
for r in $REGIONS; do
  f="$TMP/$r"
  if [ -s "$f" ]; then
    printf '\n\033[1m=== %s ===\033[0m\n' "$r"
    while IFS= read -r line; do
      printf '\033[31m%s\033[0m\n' "$line"; FOUND=$((FOUND+1))
    done < "$f"
  fi
done

printf '\n'
TOTAL=$((FOUND+G))
if [ "$TOTAL" -eq 0 ]; then
  printf '\033[32m✓ Nothing billable found in %s regions. Account is clean.\033[0m\n' "$NREG"
else
  printf '\033[31m%s billable item(s) found across %s regions.\033[0m\n' "$TOTAL" "$NREG"
  echo "Delete CloudFormation stacks FIRST; they own most of the rest."
fi
