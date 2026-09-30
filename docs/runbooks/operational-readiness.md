# Operational readiness checklist

Go through this before a **new component** reaches prod (a new AWS service, a new module, a
new app dependency) and before any **risky change** to prod (data, networking, IAM). A routine
app deploy follows `deployment.md` instead. Written in M10 for the Well-Architected review
(OPS 7): the point is that "can we run this?" gets the same answer every time, not whatever
comes to mind that day.

Record the result in the pull request description: tick what applies, and write why for
anything left unticked.

## Built the standard way

- [ ] It is in Terraform, in a module with a `terraform test` file. Nothing created by hand.
- [ ] `terraform plan` for prod was read line by line, and shows only the intended changes.
- [ ] Checkov passes, including the custom policies (`policy/README.md`), with no new skip. A
      new skip has its reason written next to it in `.pre-commit-config.yaml`.
- [ ] Infracost's comment on the PR shows the monthly cost, and it fits the remaining credit.

## Observable

- [ ] Its failure shows up somewhere: an existing alarm covers it, or a new alarm is added.
- [ ] Every new alarm has a runbook in `docs/runbooks/` and notifies the alerts SNS topic.
- [ ] Its logs go to CloudWatch with a retention set, or it has no logs worth keeping.

## Secure

- [ ] Its IAM permissions are scoped to named resources, not `*`, or the exception is written
      down.
- [ ] Its data has a level in `docs/security/data-classification.md`, and gets that level's
      controls: encryption, privacy, retention.
- [ ] Nothing new is reachable from the internet except through the ALB (Checkov `CKV_CF_2`
      enforces this for security groups).
- [ ] IAM Access Analyzer still shows 0 active findings after it is deployed.

## Recoverable

- [ ] If it stores data: how the data is backed up, and how to restore it, is written down.
- [ ] If it breaks prod: how to undo it is known before it is applied (`deployment.md` for the
      app; for infrastructure, the previous commit and a `terraform apply`).
- [ ] It survives dev's nightly destroy and rebuild without a manual step (ADR-026): run the
      destroy and the rebuild once in dev before prod.

## Documented

- [ ] Any non-obvious choice has an ADR in `docs/adr/`.
- [ ] Diagrams in `docs/diagrams/` still match what is built.
