# ADR-017: Blue/green as a second deploy strategy, alongside rolling

**Status:** accepted   **Date:** 2026-09-17   **Milestone:** M8

## Context

M3 already gives CloudForge zero-downtime rolling deploys: a new launch template version plus an ASG instance refresh, replacing instances a few at a time while the ALB drains and re-registers targets. That's a complete, working deploy path on its own. PLAN.md's decision #017 calls for a second strategy anyway — blue/green — specifically so the project can show two implemented, measured deployment strategies side by side rather than asserting "I could also do blue/green" without evidence.

Rolling and blue/green trade off differently: rolling deploys are cheap (no idle fleet) but a bad new version is validated in production, request by request, host by host — controlled, but coupled to the customer path from the first instance onward. Blue/green removes that coupling: the new version runs on a fully separate fleet, health-checked in isolation, before it takes any real traffic — the tradeoff is cost (a second fleet exists at all, even briefly) and requiring a routing layer that can shift traffic in graduated steps rather than an ASG's automatic host-by-host replacement.

## Decision

Blue/green is built on infrastructure that already existed for other reasons, not a parallel stack:

- **Green ASG** (`aws_autoscaling_group.app_green`, M8 unit 4) — same launch template as blue, `desired_capacity = 0` by default so it costs nothing idle, and deliberately has no `instance_refresh` block: it only ever scales up from zero for a deploy, so a routine rolling deploy of the blue fleet never touches it. Its size is set by the environment root's `green_asg_min_size`, `green_asg_max_size` and `green_asg_desired_capacity` variables (defaults 0 / 6 / 0).
- **Weighted ALB listener rule** (`aws_lb_listener_rule.from_cloudfront`, this unit) — the single `target_group_arn` forward action is replaced with a `forward` block holding both target groups plus explicit weights (`blue_weight`, `green_weight`, defaulting to 100/0) and `stickiness` disabled. A weight shift is `terraform apply -var="blue_weight=X" -var="green_weight=Y"`, run from `terraform/environments/<env>` — no new resources, just a state change on a rule that already exists. The root exposes both weights (M9); before that only the edge module did, so the command above had nothing to set. They are validated to be 0-100 and to sum to 100, so a typo fails at plan time instead of sending traffic nowhere. A deploy is two applies: scale green up first (`-var="green_asg_min_size=2" -var="green_asg_desired_capacity=2"`), and shift weight only once its targets are healthy.
- **Terraform-only weight changes** — shifting weight is required to go through `terraform apply`, never a raw AWS CLI `modify-rule` call. `drift.yml` (M8 unit 9) will run a scheduled `terraform plan -detailed-exitcode` and treat any difference from state as drift; if a weight shift happened outside Terraform, the next scheduled plan would report it as drift indistinguishable from an unauthorized change, even though it was a legitimate deploy.

## Alternatives considered

- **A second, fully independent ALB/target-group stack for green** — rejected: doubles the listener rules, security group surface and CloudFront origin config for no benefit over reusing the existing listener with a second target group; also breaks ADR-014's single secret-header authorization boundary across two listeners instead of one.
- **AWS CodeDeploy blue/green (native ECS/EC2 support)** — rejected: CloudForge deliberately runs no orchestrator and no CodeDeploy agent (same reasoning as ADR-004's static-binary-via-cloud-init approach); adopting CodeDeploy here for one feature would mean carrying its agent and IAM surface for a single use case the ALB can already do with a weighted rule.
- **DNS-based blue/green (two ALBs, Route 53 weighted records)** — rejected: adds DNS propagation delay to every weight shift and a second ALB to pay for and secure, when a single ALB listener rule already supports weighted forwarding natively.

## Consequences

- Two deployment strategies now exist and can be measured against each other under the same k6 load test (M8 unit 9, M12 experiments 06/07): rolling's host-by-host replacement time vs. blue/green's all-at-once cutover once the green fleet is healthy.
- A blue/green deploy costs more than rolling for its duration — the green fleet runs at full size alongside blue until the cutover completes — but that window is short and `desired_capacity = 0` at rest keeps steady-state cost identical to rolling-only.
- Every weight shift is a Terraform apply, so it shows up in `terraform plan`/`apply` history and CI logs the same way any other infrastructure change does, instead of being an untracked ALB console click.
- `drift.yml` can treat "listener rule doesn't match state" as a real signal rather than a routine false positive, because the only sanctioned way to change it is through the same tool the drift check itself runs.
