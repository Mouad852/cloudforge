# Infrastructure

Terraform module structure, environment strategy (dev/prod) and deployment mechanics.

Rolling deployments are measured in the [rolling-deploy experiment](../experiments/04-rolling-deploy.md).
The repository also implements blue/green routing through weighted ALB forwarding; its design is
recorded in [ADR-017](../adr/017-bluegreen-second-strategy.md).

The deploy and rollback procedure itself is [`../runbooks/deployment.md`](../runbooks/deployment.md).
Module-level documentation (`terraform-docs`-generated) lives alongside each module in
`terraform/modules/*/README.md`, not here.
