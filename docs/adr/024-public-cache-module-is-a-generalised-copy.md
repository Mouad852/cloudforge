# ADR-024: The public cache module is a generalised copy, not the module CloudForge runs

**Status:** accepted   **Date:** 2026-09-20   **Milestone:** M9

## Context

M9 asks for one module to be published on the public Terraform Registry. The cache module was the natural choice: it is small, self-contained, and by then had variables, validation and tests for every input. But the module CloudForge runs (`terraform/modules/cache`) is written for this project:

- `environment` is limited to `dev`, `prod` or `test`, and the secret's recovery window is `var.environment == "dev" ? 0 : 30`, an environment name baked into a resource.
- Its descriptions mention "M6" and its `name_prefix` defaults to `cloudforge`.
- It carries a `moved` block that only matters for the live state.

Publishing it unchanged would put project-internal wording and a `dev`/`prod` assumption on a public page. Changing it in place has a real cost: the security group's `description` is one of the arguments that makes AWS replace the group when it changes, and the "(M6)" text sits in exactly that description. Rewording it would replace the live Redis security group in every environment that applies the change.

## Decision

Publish a generalised copy in its own repository, [`Mouad852/terraform-aws-cache`](https://github.com/Mouad852/terraform-aws-cache), as `Mouad852/cache/aws` v0.1.0 (commit `20c6479`), and leave `terraform/modules/cache` untouched.

The copy differs in these ways, and only these:

- `environment` accepts any valid name; the length of `<environment>-<name_prefix>-redis` is validated against the 40 character replication group ID limit instead.
- The recovery window is a variable, `secret_recovery_window_in_days` (default 30, or 0), replacing the `dev` special case.
- A `tags` variable is merged into the tags of every resource that supports them.
- `name_prefix` defaults to `app`, and `apply_immediately` defaults to `false`, the safer default for a module other people will run.
- Descriptions are rewritten without project references, and the `moved` block is dropped.

The resources, their arguments (encryption at rest and in transit, AUTH token, single node, port 6379) and the outputs are the same as in the private module. Like ADR-023, it stays a single node with no failover.

## Alternatives considered

- **Publish `terraform/modules/cache` as it is.** Rejected: it would publish project jargon and the `dev`/`prod` assumption, and a user of the module could not name an environment `staging`.
- **Generalise the private module in place and have CloudForge consume the public one.** The better end state, and the one to aim for, but not now. It changes the live security group description (a replacement) and the secret's recovery window logic in prod. Dev is destroyed and recreated on a schedule (`nightly-destroy.yml`), so dev would absorb the change for free; prod would not, and prod is not the place to test a module swap.
- **Keep the module private.** Rejected: a public, versioned module with a download count is what M9 asked for, and it is the only part of the project a reader can use without cloning the repository.

## Consequences

- There are two copies. They can drift, and nothing checks that they match. The public copy has its own tests and a changelog, and its README says what it is; the private copy stays covered by `terraform/modules/cache/tests`.
- The public copy has only been tested against a mocked provider. The private module is the one that has been applied to real AWS. The differences above do not touch the resources' shapes, but "tested against a mock" is what the public README claims, and no more.
- The way out is to have CloudForge consume the published module. That becomes cheap the next time prod is rebuilt anyway, because a replaced security group is then no extra cost. At that point this ADR should be superseded by one that records the switch, and `terraform/modules/cache` removed.
- Publishing is public: anyone can pin a released version, and removing it later would break them, so each release is a commitment to keep it working.
