# Data Flow — cache-aside reads and the S3 image path (redesigned, ADR-025)

**Status: redesigned in code, not yet applied to `dev` or `prod`.** M6's diagram showed images
served straight out of S3 through CloudFront's Origin Access Control. AWS Support permanently
denied CloudFront access (ADR-025), so image reads now go through the app instead — the same
route the read and write paths already used for everything else. Once applied, the "To verify"
section below needs to be run for real and this note removed.

```mermaid
flowchart TB
    subgraph readpath["Cache-aside read path"]
        direction TB
        Client1(("Client<br/>GET /api/products or /api/products/{id}"))
        WAF1{{"WAF, REGIONAL scope<br/>associated directly with the ALB"}}
        ALB1{"ALB listener :80<br/>default action: weighted forward"}
        App1["Go app · handleListProducts /<br/>handleGetProduct"]
        CacheGet{"cache.get()<br/>key: products:list or products:&lt;id&gt;"}
        Redis1[("ElastiCache Redis<br/>TLS + AUTH · private CNAME")]
        RedisErr["Redis error<br/>logged, falls through — fails open"]
        RDS1[("RDS Postgres")]
        CacheSet["cache.set()<br/>TTL 60s (productTTL)"]
        Resp1(("JSON response"))

        Client1 --> WAF1 --> ALB1 --> App1 --> CacheGet
        CacheGet -->|hit| Resp1
        CacheGet -->|Redis error| RedisErr --> RDS1
        CacheGet -->|miss| RDS1
        RDS1 --> CacheSet --> Resp1
        CacheGet -.->|reads from| Redis1
    end

    subgraph uploadpath["S3 image write path"]
        direction TB
        Client2(("Client<br/>POST /api/products/{id}/image"))
        WAF2{{"WAF, REGIONAL scope<br/>same web ACL as above"}}
        ALB2{"ALB listener :80"}
        App2["Go app · handleUploadImage<br/>5 MiB max"]
        S3Put["objectStore.put()<br/>direct S3 PutObject<br/>(server-side, not presigned)"]
        ImagesBucket[("S3 images bucket<br/>versioned · public access blocked ·<br/>TLS-only bucket policy")]
        Invalidate["cache.del()<br/>products:list, products:&lt;id&gt;"]

        Client2 --> WAF2 --> ALB2 --> App2 --> S3Put --> ImagesBucket
        App2 -.->|invalidates on write| Invalidate
        Invalidate -.-> Redis1
    end

    subgraph readimagepath["S3 image read path"]
        direction TB
        ReaderClient(("Any client<br/>GET /api/products/{id}/image"))
        WAF3{{"WAF, REGIONAL scope<br/>same web ACL as above"}}
        ALB3{"ALB listener :80"}
        App3["Go app · handleGetImage<br/>looks up image_key, then streams it"]
        S3Get["objectStore.get()<br/>S3 GetObject via the app's own IAM role"]
        DirectS3(("Anyone hitting the S3<br/>object URL directly"))
        Forbidden403[["Denied — bucket has no public<br/>grant of any kind, for anyone"]]
        Ok200[["200 — streamed back<br/>through the app"]]

        ReaderClient --> WAF3 --> ALB3 --> App3 --> S3Get --> ImagesBucket --> Ok200
        DirectS3 -.->|bypasses the app entirely| Forbidden403
    end
```

## Why

Every path — reads, the image write, and now the image read — goes through the same WAF and the
same ALB listener. That wasn't true before: M6's `/images/*` behavior deliberately bypassed the
ALB, the ASG and Redis entirely, going straight from CloudFront to S3 via OAC, because CloudFront
could authenticate itself to S3 without the app's involvement. Nothing else in this project can
do that — the app is what's allowed to reach the images bucket (`s3:GetObject`, granted to its
IAM role since M3), so once CloudFront is gone, routing image reads through the app is the only
way to keep the bucket private *and* keep image traffic covered by the WAF and the rate limit,
rather than either serving from a public bucket or handing out presigned URLs that skip both.

The cache-aside pattern is unchanged and still deliberately fail-open: a Redis error is logged and
treated as a miss, not an error. Losing the cache should degrade the app to "every request hits
Postgres directly," not take the app down.

## To verify, once this is applied

- `terraform/modules/edge/main.tf` — one `aws_wafv2_web_acl` (`REGIONAL` scope) associated with
  `aws_lb.app` via `aws_wafv2_web_acl_association`; the listener's `default_action` forwards
  directly, weighted across the blue and green target groups.
- `app/objects.go` — `get()` calls `s3.GetObject` and returns the body plus the stored content
  type; `app/handlers.go` — `handleGetImage` looks up the product's `image_key`, then streams it.
- `curl http://<alb-dns-name>/api/products/<id>/image` → `200` with the right `Content-Type`, for
  a product that has an image.
- A direct S3 object URL for the same key → denied — the bucket has no public grant of any kind
  now, not even a CloudFront-scoped one; only the app's own IAM role can read it.
- `app/cache.go` — `productTTL = 60 * time.Second`; `get()` logs a warning and returns `(_, false)`
  on any Redis error rather than propagating it, confirming the fail-open behavior shown above.

See ADR-025 (`docs/adr/025-cloudfront-denied-edge-redesign.md`) for why this changed, ADR-013
(`docs/adr/013-private-hosted-zone.md`) for the private CNAME behind the Redis connection, and
ADR-010/ADR-014 (superseded by ADR-025) for the CloudFront-based design this replaces.
