# Capacity planning

**Status:** template prepared; measurements pending M12 E3.
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
| Generator and region | Pending E3 | WAF-window timeline |
| Highest sustainable requests/second | Pending E3 | k6 summary |
| p95 latency at that rate | Pending E3 | k6 summary |
| First sustained breach rate | Pending E3 | k6 summary and CloudWatch |
| Error rate at breach | Pending E3 | k6 summary |
| Generator CPU peak | Pending E3 | generator CPU sample |
| Dropped iterations | Pending E3 | k6 summary |
| App CPU / DB / cache bottleneck | Pending E3 | CloudWatch graph |
| Scale-out requested and time to healthy target | Pending E3 | ASG and CloudWatch |

## Conclusion

Pending E3. If the generator was the first bottleneck, this document will say that CloudForge's
capacity is unmeasured and identify the next trustworthy generator; it will not turn a generator
limit into an application number. If the application breached the target, the conclusion will
name the first constrained resource and whether the 60% CPU target-tracking policy reacted in
time.
