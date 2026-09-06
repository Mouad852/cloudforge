# ADR-016: Terraform native tests (`.tftest.hcl`) for every module

**Status:** accepted   **Date:** 2026-09-06   **Milestone:** M1

## Context

Modules take variable inputs and produce a graph of resources from them — it's easy for a bad default, a typo in a `for_each` filter, or a wrong reference to slip in without being obviously wrong just from reading the code. The usual way this gets caught is a human running `terraform plan`, reading the diff, and noticing something's off — which depends entirely on the human noticing.

Terraform 1.6+ ships a native testing framework (`.tftest.hcl` files, `terraform test` command) that can assert on planned or applied values directly, without a separate testing tool or language.

## Decision

Every module gets a `tests/<module>.tftest.hcl` file, run via `terraform test` from inside the module directory. The first one, `terraform/modules/network/tests/network.tftest.hcl`, covers the network module and mixes two kinds of checks in the same file:

- **`command = plan`** for checks that only depend on literal configuration values — subnet count, CIDR blocks, `map_public_ip_on_launch` per tier. These run in seconds and create nothing.
- **`command = apply`** for checks that need a real, AWS-assigned value to compare against — specifically, asserting that the private route table's routes never point at the Internet Gateway's actual `id`, which doesn't exist until the IGW is really created. This run block provisions a real (short-lived) VPC, NAT instance, and everything else in the module, then Terraform automatically tears it down at the end of the test.

Mixing both in one file is intentional and idiomatic — not every assertion can be answered at plan time, and forcing everything into `apply` just to test literal CIDR values would be needlessly slow and costly.

## Alternatives considered

- **Manual `plan`-and-eyeball review** — the status quo before this ADR, and the thing this ADR replaces. Works until it doesn't; catches nothing automatically and depends on the reviewer noticing.
- **A separate testing tool (Terratest, Kitchen-Terraform)** — more powerful (real Go/Ruby test code, more complex assertions), but adds a second language and toolchain to a project that already has Terraform as its primary artifact. Native tests use the same HCL syntax as the modules they test, which is a lower bar for anyone reading this repo to understand what's actually being verified.

## Consequences

- The `apply`-based run block has a real (small) cost and takes a couple of minutes, unlike the instant `plan`-based checks — a deliberate trade-off, not an oversight, since the thing it verifies genuinely can't be known before apply.
- As more modules are built (`security`, `compute`, `database`, ...), each needs its own `tests/<module>.tftest.hcl` — this is the template the later ones follow.
- `terraform test` needs to be run explicitly; it isn't yet wired into a CI pipeline or pre-commit hook in this project, so it currently depends on being run by hand when a module changes.
