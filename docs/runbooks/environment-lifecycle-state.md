# Environment lifecycle state for drift detection

`dev` and `prod` are intentionally ephemeral. A Terraform plan against an intentionally empty
environment would otherwise look exactly like destructive drift. The lifecycle signal makes that
exception explicit without hiding unexpected deletion.

## How it works

The repository variables below hold exactly `up` or `down`:

- `CLOUDFORGE_DEV_LIFECYCLE_STATE`
- `CLOUDFORGE_PROD_LIFECYCLE_STATE`

`make dev-up`, `make dev-down`, `make prod-up`, and `make CONFIRM_PROD_DOWN=YES prod-down` update
the matching variable only after their Terraform and artifact steps succeed. Down transitions also
verify empty Terraform state before recording. The CI apply workflows record `up`; the successful
nightly dev teardown verifies empty state and records `down`.

The daily drift workflow behaves as follows:

| Signal | Terraform state | Result |
|---|---|---|
| `up` | any | Run normal drift detection. |
| `down` | empty | Skip the plan: this is a documented teardown. |
| `down` | non-empty or unreadable | Open/update an inconsistency issue and fail. |
| missing or invalid | any | Run normal drift detection; do not suppress an alert. |

This is deliberately fail-safe. If a teardown succeeds but recording `down` fails, the next check
reports drift. If a rebuild succeeds but recording `up` fails, the still-`down` signal conflicts
with non-empty state and the workflow fails visibly. A scheduled check that overlaps a lifecycle
operation sees the prior state and therefore cannot silently suppress an incomplete operation.

## Initial setup

Set each value only after confirming the intended lifecycle state. Do **not** set `down` merely
because an AWS resource is absent; first verify that the matching Terraform state is empty.

In GitHub: **Settings → Secrets and variables → Actions → Variables → New repository variable**.
Create the two names above with `up` or `down` as appropriate. A GitHub CLI user can instead run:

```bash
make record-lifecycle-state ENVIRONMENT=dev STATE=up
make record-lifecycle-state ENVIRONMENT=prod STATE=down
```

The helper requires authenticated GitHub CLI access with permission to edit repository Actions
variables. If it fails after a lifecycle operation, leave the signal unchanged and resolve it; the
next drift run will fail safe rather than treating the environment as intentionally absent.

## Recovery from an inconsistency

1. Do not dismiss the issue or change the variable first.
2. Inspect the lifecycle command or CI run that last changed the environment.
3. Read the Terraform state and determine whether the environment is fully running or fully torn
   down. A partial teardown is neither state.
4. Repair or complete the lifecycle operation.
5. Record `up` only after a successful rebuild, or `down` only after a successful teardown with
   empty state. Re-run drift detection to confirm the result.
