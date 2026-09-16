# ADR-022: Redis TLS ServerName kept separate from the dial address

**Status:** accepted   **Date:** 2026-09-13   **Milestone:** M6

## Context

ElastiCache Redis (M6) has `transit_encryption_enabled` on, so the app dials it over TLS. The app doesn't dial ElastiCache's own generated hostname directly — it dials `cache.cloudforge.internal`, the private Route 53 CNAME from ADR-013, to keep app config decoupled from AWS-generated hostnames. But ElastiCache issues its TLS certificate for its own generated endpoint hostname, not for any CNAME pointed at it. Go's TLS client verifies the server certificate against a `ServerName`, which defaults to the dial address's host if left unset. With the dial address set to the CNAME and `ServerName` left unset, every connection failed hostname verification — `/readyz` timed out with the Redis health check hanging, and the failure looked like a Redis configuration or network problem rather than a certificate-name mismatch, costing a long debugging session before the actual cause surfaced.

## Decision

Add a `tlsServerName` parameter to `newCache()` (`app/cache.go`), set independently from `addr`, and use it as `tls.Config.ServerName`. `addr` stays the private CNAME (dial target, keeps ADR-013's decoupling intact); `ServerName` is set to ElastiCache's actual generated endpoint hostname (`redis_primary_endpoint`), so certificate verification checks the name the certificate was actually issued for. Wired end to end: `REDIS_TLS_SERVER_NAME` env var → `config.RedisTLSServerName` (`app/config.go`) → `newCache()` → `tls.Config.ServerName`; on the infrastructure side, `redis_tls_server_name = module.cache.redis_primary_endpoint` in `terraform/environments/dev/main.tf`, passed through the compute module's launch template user-data (`terraform/modules/compute/main.tf`).

## Alternatives considered

- **Dial ElastiCache's generated hostname directly, drop the CNAME** — rejected. Reopens exactly the coupling ADR-013 exists to avoid: app config would reference an AWS-generated name that changes if the replication group is ever replaced, instead of a stable name the app owns.
- **Disable TLS certificate verification (`InsecureSkipVerify`)** — rejected outright. Defeats the point of `transit_encryption_enabled` — the connection would still be encrypted but no longer authenticated, silently accepting a certificate for any host.
- **Custom CA / self-signed cert matching the CNAME** — not applicable; ElastiCache manages and issues its own certificate, there's no mechanism to have it issued for a customer-controlled CNAME instead.

## Consequences

- `ServerName` has to be kept in sync with whatever ElastiCache currently reports as its primary endpoint. It's wired from `module.cache.redis_primary_endpoint` rather than hardcoded, so a replacement replication group's new endpoint flows through automatically on the next `terraform apply` + instance refresh — no manual update needed.
- Two names now describe "the cache" in different layers (the CNAME for DNS/config stability, the generated endpoint for TLS identity), which is one more thing to explain to a reader of `app/cache.go` — mitigated with the comment already in that file rather than leaving it implicit.
- This is a narrow instance of a more general problem: any service that sits behind a stable custom DNS name but terminates TLS with its own AWS-issued certificate will hit the same mismatch. Worth checking for the same pattern if a similar private-CNAME-in-front-of-a-managed-service setup shows up elsewhere in this project.
