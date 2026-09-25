# Data Flow — cache-aside reads and the S3 image path (redesigned, ADR-025)

**Status: applied to `dev` and `prod`, verified 2026-09-24/25** (results at the bottom). M6's
diagram showed images served straight out of S3 through CloudFront's Origin Access Control. AWS
Support permanently denied CloudFront access (ADR-025), so image reads now go through the app
instead — the same route the read and write paths already used for everything else.

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

## Verified 2026-09-24/25, on `dev` and `prod`

Each step below was run through the public ALB, on both environments:

- `POST /api/products` → `201` with the new product and its `id`.
- `GET /api/products/<id>/image` before any upload → `404 {"error":"product has no image"}`.
- `POST /api/products/<id>/image` → `{"image_key":"products/<id>"}`.
- `GET /api/products/<id>/image` → `200`, `Content-Type: image/png`, and the exact bytes uploaded,
  with the app's security headers (`nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`).
- The test product was deleted afterwards.

Found and fixed while verifying, both in the write path:

- **S3 `PermanentRedirect` on every upload.** The compute module passed the images bucket name to
  the IAM policy but never to the app, so the app fell back to its hardcoded default
  (`cloudforge-images-dev`, without the per-environment suffix), which is not this project's
  bucket. `user_data.sh.tpl` now sets `S3_BUCKET`.
- **The WAF rejected every upload over 8 KB.** The first tests used a 58-byte file, which hid it.
  `CommonRuleSet`'s `SizeRestrictions_BODY` now only counts, and a label rule keeps the 8 KB limit
  on every route except the upload (see `traffic-flow.md`). Re-tested on `prod` with a 20 KB file:
  `200`, and it reads back as the same 20,000 bytes.

Not yet tested: that a direct S3 object URL for the same key is denied. By design it should be,
since the bucket has no public grant of any kind and only the app's IAM role can read it.

Checked by reading code rather than by request: `app/cache.go` sets `productTTL = 60 * time.Second`,
and its `get()` logs a warning and returns `(_, false)` on any Redis error instead of propagating
it, which is the fail-open behavior shown above.

See ADR-025 (`docs/adr/025-cloudfront-denied-edge-redesign.md`) for why this changed, ADR-013
(`docs/adr/013-private-hosted-zone.md`) for the private CNAME behind the Redis connection, and
ADR-010/ADR-014 (superseded by ADR-025) for the CloudFront-based design this replaces.
