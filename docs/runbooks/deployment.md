# Runbook — deploying the app, and rolling back

How a new version of the CloudStore API reaches dev and prod, what to check before and after,
and how to go back when it goes wrong. Written in M10 for the Well-Architected review (REL 8).

---

## How a deploy works

`scripts/deploy.sh <env>` does the whole thing:

1. Builds the linux/arm64 binary (`make -C app build`).
2. Uploads it to the environment's artifacts bucket at **one fixed key**, overwriting the
   previous binary. The bucket is versioned, so the previous binary is still there as an
   older object version for 90 days.
3. Creates a launch template version with no changes, labelled `deploy-<git sha>`, so the
   deploy is visible in the launch template's history.
4. Starts k6 in the background against the ALB (5 virtual users, 8 minutes).
5. Starts an ASG instance refresh that launches each replacement before terminating the old
   instance (`MinHealthyPercentage 100`, `MaxHealthyPercentage 200`). New instances download
   the binary at boot, so they run the new version.
6. Fails if the refresh fails, then waits for k6 and fails if k6's thresholds fail.

## Who deploys where

| Environment | How | When |
|---|---|---|
| dev | `app.yml`, job `deploy (dev)`, after `test / vet / govulncheck` passes and the `dev` approval | Every push to `main` touching `app/`, `scripts/deploy.sh`, `scripts/load-test.js` or `app.yml` |
| prod | **By hand**: `bash scripts/deploy.sh prod` from a machine with admin credentials | Nothing deploys the app to prod automatically. A rebuilt prod gets the binary from its own commit through `ensure-artifact.sh`; after that, prod only changes when someone runs this. |

## Before deploying to prod

- [ ] The same commit is already running in dev, deployed by `app.yml`, and its `deploy (dev)`
      job passed, including the k6 gate.
- [ ] The prod alarms are all `OK` and the `service-degraded` composite alarm is not firing:
      CloudWatch → Alarms, filter `prod-`.
- [ ] `terraform plan` in `terraform/environments/prod` shows no pending changes you did not
      expect. `deploy.sh` reads its targets from Terraform outputs, so the prod root must be
      initialised: `terraform -chdir=terraform/environments/prod init`.
- [ ] Your shell has admin AWS credentials, `k6` and Go installed, and **no leftover `GOOS` or
      `GOARCH`** from an earlier cross-build.
- [ ] Note the current binary's version ID, in case you need to roll back:
  ```sh
  aws s3api list-object-versions --bucket <artifacts bucket> --prefix cloudstore-api/ \
    --query "Versions[?IsLatest].[VersionId,LastModified]" --output text
  ```

## Deploy

```sh
bash scripts/deploy.sh prod
```

A normal run takes about 10 minutes and ends with `Deploy to prod complete`.

## After deploying

- `curl http://<prod ALB DNS name>/api/products` returns `200`.
- The newest log stream in `/cloudforge/prod/app` shows `"schema up to date"` and `"listening"`.
- Within 10 minutes, the next canary run in CloudWatch Synthetics (`prod-api-avail`) passes.

## When a deploy fails

| What you see | What it means | What to do |
|---|---|---|
| `Instance refresh ended in Failed` or `Cancelled` | New instances never became healthy. The refresh stopped, and instances it had not replaced still run the old binary, but **the S3 key already holds the new binary**, so any instance the ASG launches from now on gets the new code. | Roll back the binary (below) straight away, before the ASG replaces anything else. |
| The refresh succeeded but k6 failed | The new version is **live** and was slow or erroring under load. | Look at the `alb-5xx` and `alb-latency-p95` alarms. If they fire, roll back. |
| `InstanceRefreshInProgress` | An earlier refresh is still running, for example from an approved but stale run. | Wait for it to finish, then re-run. Only approve the run for the newest commit. |
| Every k6 request fails and the WAF's `<env>-rate-limit` metric is climbing | k6 ran into the WAF's per-IP rate limit (2,000 requests per 5 minutes). | Check `scripts/load-test.js` still sleeps 1 second per iteration (ADR-026). |

## Rolling back

**A rolling deploy has no automatic rollback.** The launch template never changes between
versions, only the object behind the fixed S3 key, so the ASG's own rollback would relaunch
instances that download the new binary again. Rolling back means putting the previous binary
back and replacing the instances:

1. Find the previous version of the binary (the second-newest):
   ```sh
   aws s3api list-object-versions --bucket <artifacts bucket> --prefix cloudstore-api/ \
     --query "Versions[].[VersionId,LastModified,IsLatest]" --output text
   ```
2. Make it the current version again:
   ```sh
   aws s3api copy-object --bucket <artifacts bucket> \
     --key cloudstore-api/cloudstore-api \
     --copy-source "<artifacts bucket>/cloudstore-api/cloudstore-api?versionId=<previous version ID>"
   ```
3. Replace the instances so they download it:
   ```sh
   aws autoscaling start-instance-refresh --auto-scaling-group-name <env>-cloudforge-app \
     --preferences '{"MinHealthyPercentage":100,"MaxHealthyPercentage":200,"InstanceWarmup":180}'
   ```
4. Verify with the checks in "After deploying".

**A blue/green deploy rolls back instantly**, because the blue fleet is still running the old
binary it downloaded at boot. Shift the traffic back, from `terraform/environments/<env>`:

```sh
terraform apply -var="blue_weight=100" -var="green_weight=0"
```

Then scale green back to zero. See ADR-017 for the full blue/green procedure.

## Known gaps

- **No automatic rollback** for rolling deploys, for the reason above. Fixing it means one S3
  key per version (for example `releases/<git sha>/cloudstore-api`) with the key written into
  each launch template version, so a template rollback is also a binary rollback.
- **prod is deployed by hand**, so it drifts behind `main`. On 2026-09-29, prod's binary was
  the one uploaded on 2026-09-25 at 11:58, before that day's app changes.
- **A failed k6 gate does not undo the deploy.** It only fails the job.
