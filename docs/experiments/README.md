# Experiments (Game Days)

One file per experiment, written in M12. This is the core evidence of the whole project — every number in `PLAN.md` §11's measurements table must trace back to a file here.

Nothing in this folder exists yet. Do not pre-fill results — an empty folder is honest; an invented measurement is not (see `PLAN.md` §18.8).

## Template

Copy `000-template.md` for every new experiment. Every field must carry a real, measured value — an unmeasured field left honestly blank is worth more than a plausible invented one.

```markdown
# Experiment NN — <name>

**Date:** <UTC>                    **Environment:** prod (ephemeral, spun up for this session)

## Hypothesis
What you expect to happen, and why, written BEFORE running it.

## Method
Exact command or AWS FIS experiment template used.

## Timeline (UTC)
| Time | Event |
|---|---|
| | Fault introduced |
| | First alarm / metric change (detection) |
| | Recovery action started |
| | Service restored |

## Measurements
- Detection time:
- Recovery time:
- Total requests during window / failed / error rate:
- Error budget consumed:

## What surprised me

## What I changed as a result

## Evidence
Screenshots: `../screenshots/12-gamedays/NN-<name>/`
```

## Planned experiments

Matches `PLAN.md` §8 (M12). Filed here once actually run:

`01-instance-failure` · `02-az-impairment` · `03-load-and-scaling` · `04-rds-failover` · `05-cache-failure` · `06-rolling-deploy` · `07-bluegreen-deploy` · `08-cpu-stress` · `09-full-rebuild` · `10-region-loss`
