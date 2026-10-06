# Cost analysis

**Status:** measured 2026-10-06; resting-cost measurement remains open because prod was rebuilt
before a three-day teardown window could be observed.
**Region:** `eu-west-3`
**Currency:** USD before AWS credits unless a row says otherwise.

This report will use Cost Explorer and the account-plan state, not public list-price estimates.
The project deliberately separates the cost of a live session from the cost of leaving resources
running between sessions.

## Required measurements

| Measurement | Actual | Source / period |
|---|---:|---|
| September total before credits | $113.26 | Cost Explorer export, 2026-09-01 through 2026-09-30 |
| Cost per prod-up day | $2.9308/day average | Cost Explorer, `Environment=prod`, 2026-10-01 through 2026-10-05; daily values were estimated |
| Cost per prod-up hour | $0.1221/hour derived | `$2.9308 / 24`; not a separate billing line |
| Resting cost after `prod-down` | Not measured | Prod was rebuilt on 2026-10-06; no three-day resting window was collected |
| Cost by tag from 2026-09-30 onward | `$17.4432` `Project=cloudforge`; `$15.4626` `Environment=prod`; `$2.7256` `Environment=dev` | Cost Explorer, 2026-09-30 through 2026-10-06; the tag slices overlap and do not include all untagged/bootstrap spend |
| Remaining Free-plan credit | `$44.11` | `aws freetier get-account-plan-state`, 2026-10-06; plan active through 2027-03-02 |

## Interpretation rules

- Report pre-credit service cost separately from remaining promotional credit.
- Label NAT instance versus NAT Gateway comparisons as list-price comparisons unless both were
  actually deployed and measured.
- Include RDS snapshots, state storage and retained logs in resting cost; do not call a teardown
  free merely because compute is absent.
- Tie any optimisation claim to a before/after Cost Explorer period.

## Conclusion

The measured prod run rate was approximately `$2.93/day` or `$0.122/hour` before credits during
2026-10-01 through 2026-10-05. For the tagged 2026-10-01 through 2026-10-06 period, the largest
CloudForge service totals were Application Load Balancer `$3.9697`, RDS `$2.8699`, ElastiCache
`$2.7000`, CloudWatch `$2.5050`, and WAF `$2.0387`; AWS marked these daily estimates as
estimated. The report does not call the environment free after teardown: snapshots, state,
retained logs and untagged/bootstrap resources still need a three-day resting measurement.
