# CloudStore API

A deliberately trivial CRUD API for "products" (create, list, get, delete, upload an image).
It exists to give the infrastructure something real to run, scale, and break — it is not the
primary focus of the project. See the root [README](../README.md) and [architecture decision
records](../docs/adr/README.md) for the AWS platform around this app.

## Endpoints

```
GET    /api/products              Redis-cached list
GET    /api/products/{id}         Redis-cached, TTL 60s
POST   /api/products
DELETE /api/products/{id}
POST   /api/products/{id}/image   → S3

GET    /healthz    shallow — 200 if the process lives. The ALB checks this only.
GET    /readyz     deep — pings Postgres + Redis. Monitored, not load-balancer-facing.
GET    /whoami     instance-id + AZ from IMDSv2 (returns "local-dev" off-EC2)
```

## Local development

```
docker compose up -d --wait   # Postgres, Redis, LocalStack
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url=http://localhost:4566 --region=eu-west-3 s3 mb s3://cloudforge-images-dev

DATABASE_URL="postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable" \
REDIS_ADDR=localhost:6379 S3_ENDPOINT=http://localhost:4566 S3_BUCKET=cloudforge-images-dev \
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  go run .
```

The app applies `migrations/` itself on startup, before it starts serving, and so do the tests.
The SQL files are embedded in the binary, so a deployed instance needs nothing else to bring a
fresh database up to date. An advisory lock stops several instances from migrating at once.
`docker compose run --rm migrate` (`make migrate`) still works if you want the schema without
starting the app.

Postgres is published on host port `5433`, not `5432` — pick your own free port if that also
collides locally.

Tests hit the same stack and skip themselves if `DATABASE_URL` isn't set:

```
DATABASE_URL="postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable" \
REDIS_ADDR=localhost:6379 go test ./...
```

## Config

Everything is env vars, read once at boot (a restart is the deployment mechanism). **The one
exception is the database password**, which is not cached: see
below.

| Var | Default | Notes |
|---|---|---|
| `PORT` | `8080` | |
| `DATABASE_URL` | local docker-compose DSN | Ignored if `DB_SECRET_ARN` is set |
| `DB_SECRET_ARN` | unset | When set, the username and the current password come from this Secrets Manager secret. The password is read again for **every new database connection**, not once at boot |
| `DB_HOST` / `DB_NAME` | `db.cloudforge.internal` / `cloudstore` | Used with `DB_SECRET_ARN` |
| `REDIS_ADDR` | `localhost:6379` | |
| `REDIS_AUTH_SECRET_ARN` | unset | When set, the Redis AUTH token is read from Secrets Manager at boot and TLS is used |
| `REDIS_TLS_SERVER_NAME` | unset | Certificate hostname when dialling through the private DNS name (ADR-022) |
| `S3_BUCKET` | `cloudforge-images-dev` | |
| `S3_ENDPOINT` | unset | Set to LocalStack's URL for local dev; unset in AWS |
| `AWS_REGION` | `eu-west-3` | |

## Behavior worth knowing

- **The database password survives rotation.** Secrets Manager rotates the RDS-managed
  password every 7 days. A `BeforeConnect` hook (`store.go`) fetches the current password for
  each new pool connection, so connections opened after a rotation log in with the new one.
  Reading it only at boot caused a 40-hour prod outage
  (`docs/incidents/2026-09-30-db-password-rotation.md`); `rotation_test.go` guards the fix.
- **Every request has a deadline.** 10 s per request, server read/write/idle timeouts, Redis
  calls that give up after 250 ms with one retry, and a 5 s Postgres connect timeout
  (`timeouts_test.go`, `docs/security/well-architected.md` REL 5).
- **Every 5xx logs its cause**, alongside the request ID, status and duration.
- **Migrations run at startup** (`migrate.go`), behind a Postgres advisory lock (ADR-026).
- **Redis fails open.** A cache read/write error is logged and falls through to Postgres —
  a dead cache degrades latency, not availability (`cache.go`).
- **`/healthz` never touches Postgres or Redis.** It's the ALB's health check; if it depended on
  a dependency, that dependency's outage would pull every instance out of rotation.
- **Graceful shutdown** on `SIGTERM`/`SIGINT`: stops accepting new connections and drains
  in-flight requests for up to 35s — longer than the ALB's 30s deregistration delay, so a
  deploy never cuts off a request mid-response.
