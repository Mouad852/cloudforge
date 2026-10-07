# Screenshots — Evidence Convention

Selected visual evidence. Screenshots sit low in the evidence hierarchy: code, git history, CI
runs, and written reports come first. A screenshot is captured only when it proves one specific
claim that text cannot, for example a CloudWatch graph spanning an experiment's incident window.
Gaps in the folder list below are deliberate: `04-load-balancing` (CloudFront era, ADR-025),
`07-observability`, and `08-cicd` are evidenced by public CI history, the incident report,
and experiment graphs instead.

## Structure

One subfolder per milestone. Folders aren't pre-created — git doesn't track empty directories, and an empty folder with a `.gitkeep` in it is noise. Create the folder the first time you actually drop a screenshot into it:

```
00-foundations/       01-networking/        02-application/
03-compute/           04-load-balancing/    05-database/
06-cache-storage-cdn/ 07-observability/     08-cicd/
09-modules/           10-security/          11-backup-dr/
12-gamedays/<NN-experiment-name>/
13-measurements/      14-portfolio/
```

## Rules

- **PNG, not JPEG** — screenshots of text/UI compress better and stay legible when zoomed.
- **Full context, not crops.** A CloudWatch graph needs its visible axis and timestamp to mean anything; a cropped panel is decoration, not evidence.
- **Redact before saving, not after.** Check for account IDs and sensitive values before a file is ever committed — not in a follow-up removal commit.
- **Filename convention:** `kebab-case-description.png`, named for the one claim it proves.

## Portfolio evidence pack

The first generated summary set is:

- [`e1-instance-failure-comparison.png`](14-portfolio/e1-instance-failure-comparison.png)
- [`e2-e4-latency-summary.png`](14-portfolio/e2-e4-latency-summary.png)
- [`e5-e6-recovery-timings.png`](14-portfolio/e5-e6-recovery-timings.png)


The project does not require a demo recording. For presentation, assemble a small visual pack from
the existing evidence: the canonical architecture diagram, one CloudWatch graph or generated
measurement graph for each important result, and the matching k6/CLI output in the experiment
report. Graphs must be labeled as summaries when they are derived from aggregate measurements rather
than raw time-series data; do not imply an application saturation point that was not measured.
