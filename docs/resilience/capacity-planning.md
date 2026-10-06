# Capacity planning

**Status:** E3 measured 2026-10-06; application saturation remains unmeasured because the
generator became the bottleneck.
**Source:** `docs/experiments/03-load-and-scaling.md`

This document will turn the E3 load test into one defensible capacity conclusion. It must use the
actual k6 summary, generator CPU sample, CloudWatch metrics and WAF-window timeline from one run;
it must not infer capacity from instance type or list-price assumptions.

## Target and method

The target is the highest sustained arrival rate for which p95 latency remains below 500 ms and
the failed-request rate remains below 1%. Run the ramp only through
`scripts/waf-benchmark-window.sh`, and report the run as generator-bounded if generator CPU reaches
85% or k6 reports dropped iterations.

## Results

| Field | Actual | Evidence |
|---|---|---|
| Generator and region | Local Windows generator; eu-west-3 prod target | WAF-window timeline |
| Highest sustainable requests/second | Not measured; generator delivered 224.11 req/s | k6 summary |
| p95 latency at delivered rate | 51.09 ms | k6 summary |
| First sustained breach rate | None observed in the application; generator dropped iterations at the 400 req/s target | k6 summary |
| Error rate at breach | 0% (268,940 requests) | k6 summary |
| Generator CPU peak | 33% | generator CPU sample |
| Dropped iterations | 609; k6 reached 500 VUs | k6 summary |
| App CPU / DB / cache bottleneck | Not established; generator/runtime was limiting | No CloudWatch graph captured |
| Scale-out requested and time to healthy target | Not measured in this run | No scale-out evidence |

## Conclusion

The run is generator-bounded. At the `400 req/s` target, the local generator reached 500 VUs and
dropped 609 iterations, while the requests it did deliver ran at p95 `51.09 ms` with zero errors.
CloudForge therefore has a measured lower bound of at least `224.11 delivered req/s` for this
run, but its true saturation point is unmeasured. A stronger or distributed generator is needed
before making an application-capacity claim; no scale-out conclusion is drawn from this run.
