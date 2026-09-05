#!/usr/bin/env bash
# aws-teardown.sh — delete billable resources in ONE region, in dependency order.
#
#   DRY RUN BY DEFAULT. Prints what it would delete and exits.
#   Pass --yes to actually delete.
#
# Usage:
#   ./scripts/aws-teardown.sh us-east-1              # dry run, shows the plan
#   ./scripts/aws-teardown.sh us-east-1 --yes        # actually delete
#
# Order matters. Each phase unblocks the next:
#   CFN stacks -> EKS -> load balancers -> EC2/RDS -> NAT -> EIP -> orphans
#
# Not covered on purpose: S3 buckets (may hold data you want), IAM users/roles,
# non-default VPCs (free; usually removed by their owning CFN stack anyway).

set -uo pipefail

REGION="${1:-}"
CONFIRM="${2:-}"
PROFILE="${AWS_PROFILE_OVERRIDE:-cloudforge}"

[ -z "$REGION" ] && { echo "usage: $0 <region> [--yes]"; exit 1; }

AWS="aws --profile $PROFILE --region $REGION --output text --no-cli-pager"
LIVE=0
[ "$CONFIRM" = "--yes" ] && LIVE=1

if [ "$LIVE" -eq 1 ]; then
  printf '\033[31m*** LIVE MODE — resources in %s WILL BE DELETED ***\033[0m\n\n' "$REGION"
else
  printf '\033[33m--- DRY RUN (%s). Nothing will be deleted. Add --yes to execute. ---\033[0m\n\n' "$REGION"
fi

ACCT=$($AWS sts get-caller-identity --query Account 2>/dev/null)
[ -z "$ACCT" ] && { echo "ERROR: credentials not working for profile '$PROFILE'"; exit 1; }
echo "Account: $ACCT   Region: $REGION"

run() {  # run <description> <command...>
  local desc="$1"; shift
  if [ "$LIVE" -eq 1 ]; then
    printf '  \033[31mDELETING\033[0m %s\n' "$desc"
    "$@" >/dev/null 2>&1 || printf '    (failed — may already be gone, or blocked by a dependency)\n'
  else
    printf '  would delete: %s\n' "$desc"
  fi
}

phase() { printf '\n\033[1m[%s]\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
phase "1. CloudFormation stacks (they own most other resources)"
# eksctl names them eksctl-<cluster>-nodegroup-* and eksctl-<cluster>-cluster.
# Nodegroup stacks MUST be deleted before the cluster stack.
STACKS=$($AWS cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE CREATE_FAILED DELETE_FAILED \
  --query 'StackSummaries[].StackName' 2>/dev/null)

for s in $STACKS; do case "$s" in *nodegroup*|*addon*) run "stack $s" $AWS cloudformation delete-stack --stack-name "$s";; esac; done
if [ "$LIVE" -eq 1 ] && [ -n "$STACKS" ]; then
  echo "  waiting for nodegroup/addon stacks to finish deleting (can take ~10 min)..."
  for s in $STACKS; do case "$s" in *nodegroup*|*addon*) $AWS cloudformation wait stack-delete-complete --stack-name "$s" 2>/dev/null;; esac; done
fi
for s in $STACKS; do case "$s" in *nodegroup*|*addon*) ;; *) run "stack $s" $AWS cloudformation delete-stack --stack-name "$s";; esac; done
if [ "$LIVE" -eq 1 ] && [ -n "$STACKS" ]; then
  echo "  waiting for remaining stacks..."
  for s in $STACKS; do case "$s" in *nodegroup*|*addon*) ;; *) $AWS cloudformation wait stack-delete-complete --stack-name "$s" 2>/dev/null;; esac; done
fi
[ -z "$STACKS" ] && echo "  none"

# ---------------------------------------------------------------------------
phase "2. EKS clusters not owned by a stack (\$0.10/hr each)"
CL=$($AWS eks list-clusters --query 'clusters[]' 2>/dev/null)
for c in $CL; do
  for ng in $($AWS eks list-nodegroups --cluster-name "$c" --query 'nodegroups[]' 2>/dev/null); do
    run "nodegroup $c/$ng" $AWS eks delete-nodegroup --cluster-name "$c" --nodegroup-name "$ng"
    [ "$LIVE" -eq 1 ] && $AWS eks wait nodegroup-deleted --cluster-name "$c" --nodegroup-name "$ng" 2>/dev/null
  done
  for fp in $($AWS eks list-fargate-profiles --cluster-name "$c" --query 'fargateProfileNames[]' 2>/dev/null); do
    run "fargate profile $c/$fp" $AWS eks delete-fargate-profile --cluster-name "$c" --fargate-profile-name "$fp"
  done
  run "EKS cluster $c" $AWS eks delete-cluster --name "$c"
done
[ -z "$CL" ] && echo "  none"

# ---------------------------------------------------------------------------
phase "3. Load balancers (must go before subnets/NAT)"
N=0
for arn in $($AWS elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' 2>/dev/null); do
  run "ALB/NLB $(basename "$arn")" $AWS elbv2 delete-load-balancer --load-balancer-arn "$arn"; N=$((N+1))
done
for n in $($AWS elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' 2>/dev/null); do
  run "classic ELB $n" $AWS elb delete-load-balancer --load-balancer-name "$n"; N=$((N+1))
done
[ "$N" -eq 0 ] && echo "  none"

# ---------------------------------------------------------------------------
phase "4. RDS instances and clusters"
N=0
for d in $($AWS rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' 2>/dev/null); do
  run "disable deletion protection on $d" $AWS rds modify-db-instance --db-instance-identifier "$d" --no-deletion-protection --apply-immediately
  run "RDS instance $d" $AWS rds delete-db-instance --db-instance-identifier "$d" --skip-final-snapshot --delete-automated-backups
  N=$((N+1))
done
for d in $($AWS rds describe-db-clusters --query 'DBClusters[].DBClusterIdentifier' 2>/dev/null); do
  run "RDS cluster $d" $AWS rds delete-db-cluster --db-cluster-identifier "$d" --skip-final-snapshot; N=$((N+1))
done
for s in $($AWS rds describe-db-snapshots --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' 2>/dev/null); do
  run "RDS manual snapshot $s" $AWS rds delete-db-snapshot --db-snapshot-identifier "$s"; N=$((N+1))
done
[ "$N" -eq 0 ] && echo "  none"

# ---------------------------------------------------------------------------
phase "5. ElastiCache"
N=0
for c in $($AWS elasticache describe-cache-clusters --query 'CacheClusters[].CacheClusterId' 2>/dev/null); do
  run "ElastiCache $c" $AWS elasticache delete-cache-cluster --cache-cluster-id "$c"; N=$((N+1))
done
[ "$N" -eq 0 ] && echo "  none"

# ---------------------------------------------------------------------------
phase "6. EC2 instances"
IDS=$($AWS ec2 describe-instances \
  --filters Name=instance-state-name,Values=running,stopped,stopping,pending \
  --query 'Reservations[].Instances[].InstanceId' 2>/dev/null)
if [ -n "$IDS" ]; then
  run "EC2 instances: $IDS" $AWS ec2 terminate-instances --instance-ids $IDS
  [ "$LIVE" -eq 1 ] && { echo "  waiting for termination..."; $AWS ec2 wait instance-terminated --instance-ids $IDS 2>/dev/null; }
else
  echo "  none"
fi

# ---------------------------------------------------------------------------
phase "7. NAT Gateways (\$0.045/hr), then Elastic IPs"
NATS=$($AWS ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' 2>/dev/null)
for n in $NATS; do run "NAT Gateway $n" $AWS ec2 delete-nat-gateway --nat-gateway-id "$n"; done
[ -z "$NATS" ] && echo "  none"
if [ "$LIVE" -eq 1 ] && [ -n "$NATS" ]; then
  echo "  waiting ~90s for NAT gateways to release their Elastic IPs..."
  sleep 90
fi
N=0
for a in $($AWS ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].AllocationId' 2>/dev/null); do
  run "Elastic IP $a" $AWS ec2 release-address --allocation-id "$a"; N=$((N+1))
done
[ "$N" -eq 0 ] && echo "  no unassociated EIPs"

# ---------------------------------------------------------------------------
phase "8. Orphans: unattached volumes, snapshots, secrets, KMS keys"
N=0
for v in $($AWS ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' 2>/dev/null); do
  run "unattached EBS volume $v" $AWS ec2 delete-volume --volume-id "$v"; N=$((N+1))
done
for s in $($AWS ec2 describe-snapshots --owner-ids self --query 'Snapshots[].SnapshotId' 2>/dev/null); do
  run "EBS snapshot $s" $AWS ec2 delete-snapshot --snapshot-id "$s"; N=$((N+1))
done
for s in $($AWS secretsmanager list-secrets --query 'SecretList[].Name' 2>/dev/null); do
  run "secret $s" $AWS secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery; N=$((N+1))
done
for k in $($AWS kms list-keys --query 'Keys[].KeyId' 2>/dev/null); do
  META=$($AWS kms describe-key --key-id "$k" --query 'KeyMetadata.[KeyManager,KeyState]' 2>/dev/null | tr '\t' '/')
  case "$META" in
    CUSTOMER/Enabled) run "KMS key $k (7-day waiting period, still \$1/mo until then)" \
                        $AWS kms schedule-key-deletion --key-id "$k" --pending-window-in-days 7; N=$((N+1));;
  esac
done
[ "$N" -eq 0 ] && echo "  none"

# ---------------------------------------------------------------------------
printf '\n'
if [ "$LIVE" -eq 1 ]; then
  printf '\033[32mTeardown pass complete for %s.\033[0m\n' "$REGION"
  echo "Some deletions are asynchronous (EKS ~10min, RDS ~5min, NAT ~2min)."
  echo "Re-run ./scripts/aws-inventory.sh in a few minutes to confirm, then again tomorrow."
  echo "Verify \$0.00/day on the Bills page 24h from now — the billing view lags."
else
  printf '\033[33mDry run only. Re-run with --yes to execute.\033[0m\n'
fi
