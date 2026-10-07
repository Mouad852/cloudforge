# Capacity planning

**Status:** Measured 2026-10-06; the generator became the bottleneck before application
saturation.
**Source:** `docs/experiments/03-load-and-scaling.md`

This record derives one defensible capacity conclusion from the k6 summary, generator CPU sample,
CloudWatch metrics, and WAF-window timeline. It does not infer capacity from instance type or
list-price assumptions.

## Target and method

The test target is the highest sustained arrival rate for which p95 latency remains below 500 ms
and failed-request rate remains below 1%. The ramp ran through
`scripts/waf-benchmark-window.sh`; a run is classified as generator-bounded if k6 reports
dropped iterations.

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
run. Its true saturation point was not established, and the run does not support a scale-out
conclusion.
