# Screenshots — Evidence Convention

Every milestone in `PLAN.md` has a `📸 EVIDENCE REQUIRED` block telling you exactly what to capture, why it matters, and what to name it. This folder is where it goes.

## Structure

One subfolder per milestone. Folders aren't pre-created — git doesn't track empty directories, and an empty folder with a `.gitkeep` in it is noise. Create the folder the first time you actually drop a screenshot into it:

```
00-foundations/       01-networking/        02-application/
03-compute/           04-load-balancing/    05-database/
06-cache-storage-cdn/ 07-observability/     08-cicd/
09-modules/           10-security/          11-backup-dr/
12-gamedays/<NN-experiment-name>/
13-dr-validation/     14-final/             15-portfolio-final/
```

## Rules

- **PNG, not JPEG** — screenshots of text/UI compress better and stay legible when zoomed.
- **Full context, not crops.** A CloudWatch graph needs its visible axis and timestamp to mean anything; a cropped panel is decoration, not evidence (`PLAN.md` §18.8).
- **Redact before saving, not after.** Check for account IDs and anything on the redaction checklist (`PLAN.md` §18.6) before the file is ever committed — not in a follow-up "remove sensitive info" commit.
- **Filename convention:** `kebab-case-description.png`, matching the "Suggested files" list in the milestone's evidence block.
