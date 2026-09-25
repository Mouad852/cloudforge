# Custom Checkov policies

CloudForge's own rules, run by Checkov next to its built-in checks: in CI (the `checkov` step of
`terraform.yml`, through `external_checks_dirs`) and locally (the `terraform_checkov` pre-commit
hook, through `--external-checks-dir`). A failing check fails the `lint` job, and `apply (dev)`
and `apply (prod)` need that job.

| ID | Rule | Why a built-in check isn't enough |
|---|---|---|
| `CKV_CF_1` | Every AWS provider sets the `Project`, `Environment`, `ManagedBy` and `Owner` default tags | Tags are set once per provider through `default_tags`. Built-in tag checks look at resources, and would flag every resource even when its provider tags it correctly. |
| `CKV_CF_2` | Ingress from the internet (`0.0.0.0/0` or `::/0`) is only allowed on TCP port 80 | The built-in checks deny specific ports (22, 3389, 80, all ports). This allows one port and denies every other. Port 80 is the ALB, the public edge since ADR-025. |

`CKV_CF_1` ignores the bare `provider "aws"` blocks in `*.tftest.hcl` files. It cannot see
resources AWS launches on Terraform's behalf: `default_tags` never reach the instances and
volumes an Auto Scaling group launches, so the compute module copies them into the launch
template's `tag_specifications` (tested in `compute.tftest.hcl`). `CKV_CF_2` covers
`aws_security_group` ingress blocks, `aws_security_group_rule` (type `ingress`) and
`aws_vpc_security_group_ingress_rule`.

Run them on their own:

```sh
checkov -d terraform/ --external-checks-dir policy/custom_checks --check CKV_CF_1,CKV_CF_2 --skip-framework terraform_plan
```
