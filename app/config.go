package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// config holds everything read at boot. No config is re-read at runtime —
// a restart is the deploy mechanism (see M3's ASG instance refresh).
type config struct {
	Port         string
	DatabaseURL  string
	RedisAddr    string
	S3Bucket     string
	S3Endpoint   string // set for LocalStack; empty in AWS, where the SDK resolves the real endpoint
	AWSRegion    string
	DrainTimeout time.Duration
}

func loadConfig(ctx context.Context) (config, error) {
	cfg := config{
		Port:         envOr("PORT", "8080"),
		RedisAddr:    envOr("REDIS_ADDR", "localhost:6379"),
		S3Bucket:     envOr("S3_BUCKET", "cloudforge-images-dev"),
		S3Endpoint:   os.Getenv("S3_ENDPOINT"),
		AWSRegion:    envOr("AWS_REGION", "eu-west-3"),
		DrainTimeout: 35 * time.Second, // must exceed the ALB's 30s deregistration delay (M4)
	}

	if arn := os.Getenv("DB_SECRET_ARN"); arn != "" {
		dsn, err := fetchDBSecret(ctx, cfg.AWSRegion, arn)
		if err != nil {
			return cfg, fmt.Errorf("fetching DB secret %s: %w", arn, err)
		}
		cfg.DatabaseURL = dsn
	} else {
		cfg.DatabaseURL = envOr("DATABASE_URL", "postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable")
	}

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// fetchDBSecret reads a Postgres DSN out of Secrets Manager. Only used in
// deployed environments (DB_SECRET_ARN set) — local dev passes DATABASE_URL
// directly, since there's no Secrets Manager to talk to.
func fetchDBSecret(ctx context.Context, region, arn string) (string, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return "", err
	}
	client := secretsmanager.NewFromConfig(awsCfg)
	out, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(arn),
	})
	if err != nil {
		return "", err
	}
	return aws.ToString(out.SecretString), nil
}
