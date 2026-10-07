# Runbook — load-test window (WAF rate-limit exemption)

**Used for:** the E3 load-and-scaling experiment and later capacity re-tests.
**Script:** `scripts/waf-benchmark-window.sh` · **Benchmark:** `scripts/capacity-test.js` (k6)

---

## Why a window is needed

The WAF's `RateLimitPerIP` rule blocks any single source after 2,000 requests in 5 minutes
(about 6.7 requests a second). A load test from one machine hits that within seconds, so
without an exception it measures the WAF, not CloudForge. Raising the limit for everyone
was rejected: it weakens protection for every client, and it needs two prod applies, each of
which rebuilds dev.

## What the exception is, and is not

- **One WAF IP set per environment**, `<env>-cloudforge-rate-limit-exempt`, empty at rest.
  It is referenced in exactly one place: a `NOT` inside the `RateLimitPerIP` rule's
  scope-down statement. An address in it skips **the rate limit only**. The managed rule
  groups (Common, KnownBadInputs, IP reputation, SQLi) and the body-size rule still inspect
  every request from it.
- **The 2,000 / 5 min / IP limit is unchanged** for every other client. The script checks the
  web ACL's lock token before and after, which proves the ACL itself did not change.
- **The rate rule keys on the TCP source address**, not a header, so a client cannot claim
  the exemption by sending `X-Forwarded-For`.
- **The list's contents are outside Terraform** (`ignore_changes = [addresses]`). Committing
  an operator's address to a public repository would be worse than the drift check not
  watching this one list. The drift check counts the list instead (backstop below).

## Running a window

1. **Pick the load generator.** Use whichever gives the most trustworthy measurement: a
   machine near `eu-west-3` with enough CPU and bandwidth to outrun one `t4g.small`, for
   example AWS CloudShell in `eu-west-3`, or a laptop on a wired connection. A phone hotspot
   measures the hotspot. The script and k6 must run **on that machine**, because the
   exemption is that machine's public egress address.
2. **Check the timing.** No `terraform plan` or `apply` may run, in CI or locally, while the
   list holds an address:
   - CI plans are posted to public issues and PR comments.
   - An apply would write the address into the versioned state bucket.
   - Avoid 05:00–07:00 UTC (drift check at 06:00) and 22:00–24:00 UTC (dev nightly destroy at
     23:00). The script warns in those hours.
   - Don't merge to `main` during a window.
3. **Run it** (Git Bash or CloudShell, from the repository root):

       scripts/waf-benchmark-window.sh prod

   The script:
   1. detects this machine's public IPv4 (or takes `--ip`) and refuses private addresses;
   2. refuses to start unless the list is empty and the web ACL references it exactly once,
      inside `RateLimitPerIP`;
   3. adds exactly that `/32` and verifies the list holds nothing else;
   4. waits 60 s for propagation, then runs the benchmark with a hard cap
      (`--max-minutes`, default 30);
   5. empties the list in an exit trap and verifies it is empty, on success, failure,
      Ctrl-C, `SIGTERM` or a dropped session.

   Pass a different benchmark after `--`; it receives `TARGET_URL`. For example:

       scripts/waf-benchmark-window.sh prod --max-minutes 25 -- k6 run scripts/capacity-test.js

4. **Read the results** in the output directory (`~/cloudforge-benchmarks/<env>-<UTC>/` by
   default; the script refuses any path inside a git repository):
   - `timeline.log`: UTC times for window opened, exemption active, benchmark start and end,
     window closed, and list verified empty. The source appears only as a short hash, so this
     file can be pasted into the experiment report.
   - `generator-cpu.csv` and the peak logged in the timeline; k6's `dropped_iterations`.
   - `k6-summary.json`, `k6-metrics.csv` (per request), `benchmark.log`.

## Is the number real?

The run measures the load generator if:

- the generator's CPU peaked at 85% or more (the timeline warns), or
- k6 reported dropped iterations (the requested arrival rate was never sent).

If either happened, the report says so, and the number is **not** CloudForge's capacity.
Re-run from a stronger generator, or report the result as a lower bound. If no generator can
saturate the API, say that too.

## If the window did not close

The script exits 3 and prints this fallback if it cannot verify the list is empty. From any
machine with AWS credentials:

    scripts/waf-benchmark-window.sh prod --cleanup-only

Or in the console: **WAF & Shield → IP sets** (region `eu-west-3`) →
`prod-cloudforge-rate-limit-exempt` → select every address → **Delete**. Then confirm the list
is empty. **Never screenshot the list while it holds an address.**

**Backstop:** if the generator itself dies, so that no trap can run, the daily drift check
(`drift.yml`, 06:00 UTC) counts the list. If it is not empty, the job fails and opens the issue
"WAF rate-limit exemption left active (<env>)", showing the count only. Worst-case exposure is
one source address skipping the rate limit (and only the rate limit) until that check runs.

## Keep the address private

The address must never appear in:

- committed files
- Terraform state
- screenshots
- issues
- experiment reports

The script never writes it to the timeline. CloudTrail records it in the `UpdateIPSet` events,
which stay inside the account.
