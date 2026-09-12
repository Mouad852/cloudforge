.PHONY: dev-up dev-down

TF_DIR := terraform/environments/dev
DB_INSTANCE := dev-cloudforge-db

# Applies the full dev environment. If a manual snapshot exists from a
# previous dev-down (the database module always takes a final snapshot on
# destroy - ADR-015), restores the database from the most recent one
# instead of creating an empty database.
dev-up:
	@SNAP=$$(aws rds describe-db-snapshots \
		--db-instance-identifier $(DB_INSTANCE) \
		--snapshot-type manual \
		--query "reverse(sort_by(DBSnapshots[?Status=='available'],&SnapshotCreateTime))[0].DBSnapshotIdentifier" \
		--output text 2>/dev/null); \
	if [ -n "$$SNAP" ] && [ "$$SNAP" != "None" ]; then \
		echo "Restoring $(DB_INSTANCE) from snapshot: $$SNAP"; \
		cd $(TF_DIR) && terraform apply -var="snapshot_identifier=$$SNAP"; \
	else \
		echo "No prior snapshot found - creating a fresh database"; \
		cd $(TF_DIR) && terraform apply; \
	fi

# Destroys the dev environment. skip_final_snapshot = false on the database
# means a final snapshot is always taken first - dev-up finds and restores
# from it automatically, so tearing down dev never actually loses data.
dev-down:
	cd $(TF_DIR) && terraform destroy
