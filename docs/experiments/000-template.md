# Experiment NN — <name>

**Date:** <UTC>                    **Environment:** prod (session start/stop: <UTC> / <UTC>)

## Hypothesis

What you expect to happen, and why — written **before** running the experiment.

## Method

The exact fault command (raw AWS CLI invocation, not a paraphrase; AWS FIS is not available on this account's plan) and the k6 load running during it.

## Timeline (UTC)

| Time | Event |
|---|---|
| | Fault introduced |
| | Detection: which alarm or signal, and did the one that should have fired actually fire? |
| | Recovery action started |
| | Service restored |

## Measurements

- Detection time:
- Recovery time:
- k6: total requests during window / failed / error rate:
- Error budget consumed (against `docs/observability/slo.md`):
- Steady state confirmed (how):

## What surprised me

Genuine surprise, not a rehearsed observation. If nothing surprised you, say so and explain why the result was fully predictable.

## What I changed as a result

If nothing changed, say why the current configuration was already correct — don't leave this blank.

## Evidence

One CloudWatch graph spanning the whole incident window (timestamps visible) in `../screenshots/12-gamedays/NN-<name>/`, and the k6 summary pasted as text above. No other screenshots unless they prove something specific.
