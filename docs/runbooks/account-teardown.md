# Runbook — Full account teardown (console)

**Purpose:** return an AWS region to $0.00/day. Used first for the Pitstop EKS cleanup
(2026-09-04), and reusable whenever `terraform destroy` leaves something behind.

**Rule:** delete in dependency order. Each phase unblocks the next. Skipping ahead
produces `DependencyViolation` errors and half-deleted CloudFormation stacks.

---

## Phase 0 — Set the region

Region selector, top right → **US East (N. Virginia) / us-east-1**.

Nothing below works if you are in the wrong region. Every phase is region-scoped
except IAM, S3, CloudFront and Route 53.

Before starting, get the ground truth on what is actually costing money:
**Billing → Cost Explorer** → daily granularity, last 7 days, group by **Service**.

---

## Phase 1 — Kubernetes-created load balancers  ⚠️ BEFORE CloudFormation

Load balancers created by the AWS Load Balancer Controller or an Istio ingress
gateway are **not** owned by CloudFormation. They hold ENIs in the VPC subnets and
will block the cluster stack's deletion if left in place.

**EC2 → Load Balancers** → delete every one.
**EC2 → Target Groups** → delete any left orphaned.

Verify: both lists empty.

---

## Phase 2 — CloudFormation stacks

**CloudFormation → Stacks.** An `eksctl`-created cluster produces several:

```
eksctl-<cluster>-cluster                  <- delete LAST
eksctl-<cluster>-nodegroup-<name>         <- delete FIRST
eksctl-<cluster>-addon-vpc-cni            <- delete FIRST
eksctl-<cluster>-addon-iamserviceaccount-*  <- delete FIRST
```

1. Delete every **nodegroup**, **addon** and **iamserviceaccount** stack.
2. Wait for each to reach `DELETE_COMPLETE` (~5–10 min; node draining is the slow part).
3. Then delete the **cluster** stack.

CloudFormation enforces this order via stack exports, so it will refuse the cluster
stack while nodegroup stacks exist. That is expected, not an error.

**If a stack goes to `DELETE_FAILED`:** open it → **Events** tab → read the first
failure from the bottom. It names the blocking resource. Usually a leftover ENI,
security group, or a load balancer missed in Phase 1. Delete that, then retry.

---

## Phase 3 — EKS clusters not owned by a stack

**EKS → Clusters.** If anything remains:
Compute tab → delete **node groups** first, wait, then delete the cluster.

> $0.10/hour per cluster with zero workloads. This is the expensive one.

---

## Phase 4 — RDS

**RDS → Databases.** For each:

1. **Modify** → uncheck **Enable deletion protection** → Continue → **Apply immediately**.
   (Delete will silently refuse while this is on.)
2. **Actions → Delete** → uncheck *Create final snapshot* → uncheck *Retain automated backups*
   → type `delete me` → Delete.

Also check **RDS → Snapshots → Manual** and delete any (they bill for storage).

---

## Phase 5 — ElastiCache, EC2

**ElastiCache → Redis/Memcached caches** → delete.
**EC2 → Instances** → select all → Instance state → **Terminate**. Wait for `terminated`.

---

## Phase 6 — NAT Gateways, then Elastic IPs

Order matters: a NAT Gateway holds its Elastic IP until it is fully deleted.

**VPC → NAT Gateways** → delete each. Wait ~2 min for state `deleted`.
**EC2 → Elastic IPs** → release every address with no association.

> NAT Gateway: $0.045/hr ($33/mo). Idle Elastic IP: $0.005/hr.

---

## Phase 7 — Storage orphans

**EC2 → Volumes** → filter state `available` (= unattached) → delete. These bill while idle.
**EC2 → Snapshots** → owned by me → delete.
**EC2 → AMIs** → owned by me → deregister (their backing snapshots bill).
**ECR → Repositories** → delete. Container images bill at $0.10/GB/month, and a
Pitstop-sized image set is not nothing.
**EFS → File systems** → delete if any.

---

## Phase 8 — Secrets, keys, logs

**Secrets Manager → Secrets** → delete. Choose the shortest recovery window, or
"delete immediately" if offered. ($0.40/secret/month.)

**KMS → Customer managed keys** → Key actions → **Schedule key deletion** → 7 days
(the minimum AWS allows).
> These keep billing $1/month for the 7-day window. Unavoidable. They will still
> appear in the next inventory — that is not a failed teardown.

**CloudWatch → Log groups** → delete `/aws/eks/*` and any application groups.
Cheap, but they accumulate.

---

## Phase 9 — VPCs

**VPC → Your VPCs** → delete any non-default VPC that survived its stack.

If deletion is blocked, the error names the dependency. Work through in this order:
NAT gateways → endpoints → network interfaces → subnets → route tables →
internet gateways → security groups.

---

## Phase 10 — Global services

Region-independent, so check once:

- **S3 → Buckets** — review by name before deleting. Empty the bucket first; a
  non-empty bucket refuses deletion. **Check contents before emptying.**
- **CloudFront → Distributions** — disable, wait for `Deployed`, then delete.
- **Route 53 → Hosted zones** — $0.50/month each.
- **IAM** — leave users and roles alone. They are free, and deleting the wrong one
  locks you out.

---

## Phase 11 — Other regions

Repeat Phases 1–9 in every region you have touched. Known: **us-east-1**,
**eu-north-1** (the `EUN1-Requests-Tier1` SNS line item).

Fast check per region: **VPC → Your VPCs**. A non-default VPC means something was
built there. Also **EC2 → Instances** with the state filter cleared.

---

## Verification

1. Immediately: re-walk Phases 1–9. Asynchronous deletions (EKS ~10 min, RDS ~5 min,
   NAT ~2 min) may still have been in flight.
2. **+24 hours:** Billing → **Bills** → confirm region spend stopped increasing.
   The billing view lags roughly a day, so same-day numbers prove nothing.
3. **+48 hours:** Billing → **Credits** → confirm "estimated amount used" is flat.

Target: **$0.00/day**, with only the KMS 7-day tail outstanding.

---

## Why this matters beyond today

This loop — provision, verify, destroy, verify the bill — is the operating discipline
CloudForge is built on. The account is on the post-July-2025 model with **no 12-month
free tier** (see PLAN.md §11.4), so every running hour draws down a finite $158.
Getting fluent at teardown is what makes the ephemeral strategy in PLAN.md §2 work.
