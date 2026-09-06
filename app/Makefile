.PHONY: dev-up dev-down migrate bucket test build run

dev-up:
	docker compose up -d --wait
	$(MAKE) migrate
	$(MAKE) bucket

dev-down:
	docker compose down -v

migrate:
	docker compose run --rm migrate

# LocalStack doesn't pre-create buckets — the app assumes S3_BUCKET already exists,
# same as in AWS where Terraform (module storage/) creates it ahead of time.
# Dummy credentials: LocalStack doesn't check them, but the SDK requires something present.
bucket:
	AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
	aws --endpoint-url=http://localhost:4566 --region=eu-west-3 \
		s3 mb s3://cloudforge-images-dev || true

test:
	go test ./...

# Matches PLAN.md's deploy target: arm64 (Graviton, ADR-003), no CGO, stripped.
build:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o bin/cloudstore-api .

run:
	go run .
