.PHONY: dev-up dev-down prod-up prod-down restore-test ensure-redis-secret record-lifecycle-state

AWS_REGION ?= eu-west-3

DEV_TF_DIR := terraform/environments/dev
DEV_DB_INSTANCE := dev-cloudforge-db
PROD_TF_DIR := terraform/environments/prod
PROD_DB_INSTANCE := prod-cloudforge-db
RESTORE_ENV ?= prod

# Applies the full dev environment. If a manual snapshot exists from a
# previous dev-down (the database module always takes a final snapshot on
# destroy - ADR-015), restores the database from the most recent one
# instead of creating an empty database. Then uploads the app binary if the
# freshly created artifacts bucket has none - the instances wait for it.
dev-up:
	@SNAP=$$(aws rds describe-db-snapshots \
		--region $(AWS_REGION) \
		--db-instance-identifier $(DEV_DB_INSTANCE) \
		--snapshot-type manual \
		--query "reverse(sort_by(DBSnapshots[?Status=='available' && starts_with(DBSnapshotIdentifier, '$(DEV_DB_INSTANCE)-final-')],&SnapshotCreateTime))[0].DBSnapshotIdentifier" \
		--output text 2>/dev/null); \
	if [ -n "$$SNAP" ] && [ "$$SNAP" != "None" ]; then \
		echo "Restoring $(DEV_DB_INSTANCE) from snapshot: $$SNAP"; \
		cd $(DEV_TF_DIR) && terraform apply -var="snapshot_identifier=$$SNAP"; \
	else \
		echo "No prior snapshot found - creating a fresh database"; \
		cd $(DEV_TF_DIR) && terraform apply; \
	fi
	AWS_DEFAULT_REGION=$(AWS_REGION) bash scripts/ensure-artifact.sh dev
	bash scripts/record-lifecycle-state.sh dev up

# Destroys the dev environment. skip_final_snapshot = false on the database
# means a final snapshot is always taken first - dev-up finds and restores
# from it automatically, so tearing down dev never actually loses data.
dev-down:
	cd $(DEV_TF_DIR) && terraform destroy
	@state_file=$$(mktemp); trap 'rm -f "$$state_file"' EXIT; \
	cd $(DEV_TF_DIR) && terraform state list > "$$state_file"; \
	test ! -s "$$state_file" || { echo "Refusing to record dev as down: Terraform state is not empty." >&2; exit 1; }
	bash scripts/record-lifecycle-state.sh dev down

# Turns off prod deletion protection immediately, then destroys the environment.
# This is a full teardown: the final RDS snapshot preserves relational data,
# but the artifacts, images and ALB-log buckets are deleted permanently.
prod-down:
	@test "$(CONFIRM_PROD_DOWN)" = "YES" || { echo "Refusing prod teardown. Run: make CONFIRM_PROD_DOWN=YES prod-down" >&2; exit 1; }
	@echo "WARNING: prod-down permanently deletes prod artifacts, canary output, product images and ALB access logs."
	@echo "==> prod-down: disabling deletion protection at $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	cd $(PROD_TF_DIR) && terraform apply \
		-var="db_deletion_protection=false" \
		-var="db_apply_immediately=true" \
		-var="alb_deletion_protection=false"
	@echo "==> prod-down: destroying with a final DB snapshot at $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	cd $(PROD_TF_DIR) && terraform destroy \
		-var="db_deletion_protection=false" \
		-var="db_apply_immediately=true" \
		-var="alb_deletion_protection=false"
	@state_file=$$(mktemp); trap 'rm -f "$$state_file"' EXIT; \
	cd $(PROD_TF_DIR) && terraform state list > "$$state_file"; \
	test ! -s "$$state_file" || { echo "Refusing to record prod as down: Terraform state is not empty." >&2; exit 1; }
	bash scripts/record-lifecycle-state.sh prod down
	@echo "==> prod-down: complete at $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Rebuilds prod only from its newest final snapshot. It deliberately refuses
# to create an empty database: prod-up is the tested recovery path, not a
# fresh-environment shortcut.
prod-up:
	AWS_DEFAULT_REGION=$(AWS_REGION) bash scripts/ensure-redis-secret.sh prod
	@echo "==> prod-up: finding the newest final snapshot at $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	@SNAP=$$(aws rds describe-db-snapshots \
		--region $(AWS_REGION) \
		--db-instance-identifier $(PROD_DB_INSTANCE) \
		--snapshot-type manual \
		--query "reverse(sort_by(DBSnapshots[?Status=='available' && starts_with(DBSnapshotIdentifier, '$(PROD_DB_INSTANCE)-final-')],&SnapshotCreateTime))[0].DBSnapshotIdentifier" \
		--output text 2>/dev/null); \
	if [ -z "$$SNAP" ] || [ "$$SNAP" = "None" ]; then \
		echo "No available final snapshot for $(PROD_DB_INSTANCE); refusing to create an empty prod database." >&2; \
		exit 1; \
	fi; \
	echo "Restoring $(PROD_DB_INSTANCE) from snapshot: $$SNAP"; \
	cd $(PROD_TF_DIR) && terraform apply -var="snapshot_identifier=$$SNAP"
	@echo "==> prod-up: ensuring the rebuild has an artifact at $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	AWS_DEFAULT_REGION=$(AWS_REGION) bash scripts/ensure-artifact.sh prod
	bash scripts/record-lifecycle-state.sh prod up
	@echo "==> prod-up: complete at $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

ensure-redis-secret:
	AWS_DEFAULT_REGION=$(AWS_REGION) bash scripts/ensure-redis-secret.sh $(RESTORE_ENV)

record-lifecycle-state:
	@test -n "$(ENVIRONMENT)" && test -n "$(STATE)" || { echo "Run: make record-lifecycle-state ENVIRONMENT=<dev|prod> STATE=<up|down>" >&2; exit 1; }
	bash scripts/record-lifecycle-state.sh $(ENVIRONMENT) $(STATE)

# Manual, destructive-cost DR evidence only: asks for confirmation before it
# writes a marker and creates a temporary RDS instance, then always removes it.
# Example: make restore-test RESTORE_ENV=prod
restore-test:
	AWS_REGION=$(AWS_REGION) bash scripts/restore-test.sh $(RESTORE_ENV)
