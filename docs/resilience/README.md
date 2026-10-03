# Resilience

- `capacity-planning.md` — written in M13 (`PLAN.md` §9) from the M12 load test (E3): requests
  per second one `t4g.small` sustains at the p95 latency target, the saturation point and its
  bottleneck, and whether the 60% CPU target-tracking setting is right, derived from those
  numbers rather than guessed. If the WAF's per-IP rate limit bounded the test, the document
  says so. **Not written yet.**

Failure-injection results live in [`../experiments/`](../experiments/), not here — this folder is
about steady-state capacity behavior, not failure behavior.
