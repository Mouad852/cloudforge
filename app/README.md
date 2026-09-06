# CloudStore API

A deliberately trivial CRUD API for "products" (create, list, get, delete, upload an image).
It exists to give the infrastructure something real to run, scale, and break — it is not the
point of this project. See the root `PLAN.md` (§ M2) and `docs/adr/` for the actual portfolio
content: the AWS architecture around this app.

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
docker compose run --rm migrate
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url=http://localhost:4566 --region=eu-west-3 s3 mb s3://cloudforge-images-dev

DATABASE_URL="postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable" \
REDIS_ADDR=localhost:6379 S3_ENDPOINT=http://localhost:4566 S3_BUCKET=cloudforge-images-dev \
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  go run .
```

Postgres is published on host port `5433`, not `5432` — pick your own free port if that also
collides locally.

Tests hit the same stack and skip themselves if `DATABASE_URL` isn't set:

```
DATABASE_URL="postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable" \
REDIS_ADDR=localhost:6379 go test ./...
```

## Config

Everything is env vars, read once at boot (a restart is the deploy mechanism — see M3's ASG
instance refresh):

| Var | Default | Notes |
|---|---|---|
| `PORT` | `8080` | |
| `DATABASE_URL` | local docker-compose DSN | Ignored if `DB_SECRET_ARN` is set |
| `DB_SECRET_ARN` | unset | When set, the DSN is fetched from Secrets Manager at boot instead |
| `REDIS_ADDR` | `localhost:6379` | |
| `S3_BUCKET` | `cloudforge-images-dev` | |
| `S3_ENDPOINT` | unset | Set to LocalStack's URL for local dev; unset in AWS |
| `AWS_REGION` | `eu-west-3` | |

## Behavior worth knowing

- **Redis fails open.** A cache read/write error is logged and falls through to Postgres —
  a dead cache degrades latency, not availability (`cache.go`).
- **`/healthz` never touches Postgres or Redis.** It's the ALB's health check; if it depended on
  a dependency, that dependency's outage would pull every instance out of rotation.
- **Graceful shutdown** on `SIGTERM`/`SIGINT`: stops accepting new connections and drains
  in-flight requests for up to 35s — longer than the ALB's 30s deregistration delay (M4), so a
  deploy never cuts off a request mid-response.
