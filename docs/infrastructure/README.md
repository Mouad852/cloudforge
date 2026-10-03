# Infrastructure

Terraform module structure, environment strategy (dev/prod) and deployment mechanics.

- `deployment-strategies.md` — optional (M13, `PLAN.md` §9). Rolling (ASG instance refresh,
  launch before terminate) measured in the M12 rolling-deploy experiment; blue/green (ALB
  weighted forward) either measured in the optional E7 or stated as implemented but not
  exercised (ADR-017). May live inside the E4 experiment report instead. **Not written yet.**

The deploy and rollback procedure itself is [`../runbooks/deployment.md`](../runbooks/deployment.md).
Module-level documentation (`terraform-docs`-generated) lives alongside each module in
`terraform/modules/*/README.md`, not here.
