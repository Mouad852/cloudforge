# Screenshots — Evidence Convention

Selected visual evidence, by milestone. Screenshots sit low in the evidence hierarchy (`PLAN.md` §9, M14): code, git history, CI runs and written reports come first. A screenshot is captured only when it proves one specific claim that text cannot, for example a CloudWatch graph spanning an experiment's incident window. Gaps in the folder list below are deliberate: `04-load-balancing` (CloudFront era, ADR-025), `07-observability` and `08-cicd` are proven by the public CI history, the incident report and the M12 experiment graphs instead.

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
- **Full context, not crops.** A CloudWatch graph needs its visible axis and timestamp to mean anything; a cropped panel is decoration, not evidence (`PLAN.md` Appendix C).
- **Redact before saving, not after.** Check for account IDs and anything on the redaction checklist (`PLAN.md` Appendix C) before the file is ever committed — not in a follow-up "remove sensitive info" commit.
- **Filename convention:** `kebab-case-description.png`, named for the one claim it proves.
