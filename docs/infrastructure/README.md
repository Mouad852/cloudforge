# Infrastructure

Terraform module structure, environment strategy (dev/prod), and deployment mechanics.

- `deployment-strategies.md` — rolling (ASG instance refresh) vs. blue/green (ALB target-group weight shift), with a measured comparison. Written in M8, once both are implemented and load-tested. **Not written yet.**

Module-level documentation (`terraform-docs`-generated) lives alongside each module in `terraform/modules/*/README.md`, not here — this folder is the cross-module narrative, not per-module reference.
