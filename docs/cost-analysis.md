# Cost analysis

**Status:** template prepared; measured values pending M13.
**Region:** `eu-west-3`
**Currency:** USD before AWS credits unless a row says otherwise.

This report will use Cost Explorer and the account-plan state, not public list-price estimates.
The project deliberately separates the cost of a live session from the cost of leaving resources
running between sessions.

## Required measurements

| Measurement | Actual | Source / period |
|---|---:|---|
| September total before credits | Pending M13 | Cost Explorer, 2026-09-01 through 2026-09-30 |
| Cost per prod-up day | Pending M13 | Cost Explorer, tagged resources |
| Cost per prod-up hour | Pending M13 | Cost Explorer, tagged resources |
| Resting cost after `prod-down` | Pending M13 | At least three days after teardown |
| Cost by tag from 2026-09-30 onward | Pending M13 | Cost allocation tags / Cost Explorer |
| Remaining Free-plan credit | Pending current check | Account-plan state, timestamp recorded with run |

## Interpretation rules

- Report pre-credit service cost separately from remaining promotional credit.
- Label NAT instance versus NAT Gateway comparisons as list-price comparisons unless both were
  actually deployed and measured.
- Include RDS snapshots, state storage and retained logs in resting cost; do not call a teardown
  free merely because compute is absent.
- Tie any optimisation claim to a before/after Cost Explorer period.

## Conclusion

Pending M13. The final report will explain the measured cost of a prod session, the resting cost
between sessions, the largest fixed contributors, and which production-grade alternatives were
rejected for this credit-bounded portfolio workload.
