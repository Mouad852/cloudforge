# Security

- `threat-model.md` — what an attacker would try, what stops them at each layer, what was consciously not defended against. Written in M10.
- `well-architected.md` — the AWS Well-Architected Tool review: every finding, what was remediated, what was accepted and why. Written in M10.
- `encryption-inventory.md` — every data store, at rest and in transit, with its key type. Written in M10.

**None of these exist yet.** IAM policies and the GitHub OIDC trust policy get documented here as they're built (M3, M8) rather than held back for M10 — see the evidence checkpoints in `PLAN.md`.

## M3 — the app instance role (`dev-cloudforge-app`)

`terraform/modules/compute` hand-writes one inline policy for the EC2 instance role, plus the
AWS-managed `AmazonSSMManagedInstanceCore`. Every statement is scoped to a specific resource
except one, which is a documented, unavoidable exception — never a blanket `Resource: "*"`.

| Statement | Action(s) | Resource | Why |
|---|---|---|---|
| `ReadArtifacts` | `s3:GetObject` | The one `artifacts` bucket, object-level | This is how the instance pulls the app binary at boot (ADR-004). Nothing else needs to read this bucket. |
| `ReadWriteImages` | `s3:GetObject`/`PutObject`/`DeleteObject` | The one `images` bucket (M6, not built yet — see the note below) | The app's own product-image upload feature (M2). No bucket-level actions (no `ListBucket`, no delete-the-bucket) — only what reading/writing individual objects needs. |
| `ReadAppSecrets` | `secretsmanager:GetSecretValue` | Two ARN *patterns*, not two literal ARNs | The RDS master password (M5) uses AWS's own auto-generated `rds!db-<id>` naming — we can't know the exact ARN before RDS exists, so this is scoped to the fixed `rds!` prefix only AWS-managed RDS secrets ever use. The Redis AUTH token (M6) uses a name *we* chose in advance (`cloudforge/dev/redis-auth`), so the ARN pattern already matches what M6 will create — no policy change needed when that secret shows up. |
| `PutCustomMetrics` | `cloudwatch:PutMetricData` | `*` (see below) | **The one exception.** `PutMetricData` has no ARN format at all — AWS's own IAM reference lists it as one of a handful of actions that only support `Resource: "*"`. The `Condition` block (`cloudwatch:namespace = CloudForge/EC2`) is the real scoping mechanism: this role can only ever publish into our own metrics namespace, never anyone else's. Same shape as a wildcard, different effect. |
| `AppLogGroup` | `logs:*` | The one app log group, plus its log streams (`:*` suffix) | Action-level wildcard, resource-level lockdown — this role can do anything to *this* log group (create streams, put events, describe it) and nothing to any other log group in the account. |

**Why the images/Secrets Manager resources are referenced before they exist:** M3 (compute)
comes before M5 (RDS) and M6 (storage/cache) in build order, but the IAM policy needed to be
complete on day one, not patched in later. S3 ARNs and Secrets Manager name *patterns* are
predictable ahead of time even when the resources aren't built yet, so the policy is written
once, correctly, and M5/M6 only need to create matching resources — not touch this policy at
all.

**The NAT instance also got an IAM role during M3** (`AmazonSSMManagedInstanceCore` only,
added mid-milestone) — see ADR-008's "Known issue" section for why: it made the NAT box
debuggable via SSM independently of whether it was actually forwarding traffic correctly,
which turned out to matter a great deal.
