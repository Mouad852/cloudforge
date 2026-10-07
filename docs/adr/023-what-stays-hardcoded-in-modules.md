# ADR-023: What stays hardcoded in modules, and why

**Status:** accepted   **Date:** 2026-09-20   **Milestone:** M9

## Context

Not every hardcoded value deserves a module input. Every input is a promise: it needs a default,
validation, a test that it reaches the resource, and documentation. A knob nobody can safely turn
adds cost without benefit and creates combinations the tests do not cover.

## Decision

A value becomes a variable when at least one of these is true:

- a plausible caller would want a different value, for example the health check interval, the WAF rate limit or the CloudFront price class;
- it is a value environments legitimately need to vary, for example instance sizes, backup and log
  retention, `multi_az`, or deletion protection.

Every variable defaults to the value the live environments already run, so introducing it changes no plan. Bounds in `validation` come from the AWS limits, not from taste.

A value stays hardcoded, on purpose, when it falls into one of these groups:

- **Coupled to another value or to the app.** `instance_warmup = 180` on the instance refresh follows `health_check_grace_period`; `heartbeat_timeout = 90` on the lifecycle hooks follows the app's drain timeout. The edge listener port 80 is repeated in the ALB security group's ingress rule and CloudFront's `http_port`, and the ALB has no certificate. Changing one alone breaks the others, and Terraform cannot enforce the relationship across resources, so exposing them separately would only invite a broken combination.
- **The definition of an SLO.** The alarm thresholds, periods and evaluation periods in `modules/observability` are the SLIs from ADR-020, and the runbooks quote them ("more than 10 5xx responses in 5 minutes"). Dev and prod must alarm identically, or a game day in one says nothing about the other. The two thresholds that depend on the instance size, `rds_max_connections_threshold` and `billing_budget_usd`, are variables.
- **A security invariant.** Encryption at rest and in transit, block-public-access, IMDSv2 (`http_tokens = "required"`), the CloudFront origin-access-control signing, the HSTS and other security headers, the WAF managed rule groups and the secret-header check from ADR-014. These are the reason the module exists. A variable that could switch one off would be a way to ship an insecure environment by editing a tfvars file, so they are fixed.
- **Structural, not a tunable.** `nat_type` is described in ADR-008. The cache's `num_cache_clusters = 1` and `automatic_failover_enabled = false` are the same kind of case: a second node needs failover on, the observability alarms watch only `<replication-group-id>-001`, and checkov's CKV2_AWS_50 skip in `.pre-commit-config.yaml` is justified by the single node. That is a feature to build with its own tests, not a number to expose. Until then prod's cache is a single node, as it is in dev.
- **Fixed by AWS.** The managed cache policy IDs, and constants such as the Redis port 6379.

## Alternatives considered

- **A variable for every literal.** Rejected: it multiplies the untested combinations, buries the variables that matter in the README and makes the "dev and prod differ only in ..." rule impossible to review, because tfvars could then differ in anything.
- **Leave everything as it was and only document the gaps.** Rejected: it fails the point of M9, because a caller who needs a different health check or retention would have to fork the module.
- **Make the coupled values derived instead of fixed.** Considered for the instance warmup (a multiple of the grace period). Not done: the ratio is a judgement about this app's boot time, and hiding it in a formula makes it harder to see and to change.

## Consequences

- The module READMEs list only inputs that are safe to change, and each has a test that it reaches the resource and a test that an out-of-range value is rejected.
- Making one of the fixed values a variable later is a normal change: add the variable with today's value as the default, a `validation` and tests. This ADR should then be updated, not ignored.
- The `nat_type` and cache node-count gaps stay open. Both are recorded here or in ADR-008, so a reviewer reading the code finds the reason, not a missing feature.

> **Status update (2026-10-03):** one alarm threshold is no longer fixed.
> `asg-in-service-instances` now follows the environment's `asg_min_size` through a
> `modules/observability` variable with validation and tests. It is a fleet-floor alarm,
> coupled to the ASG's size, not an SLO threshold.
