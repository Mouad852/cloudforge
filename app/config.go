package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// config holds everything read at boot. No config is re-read at runtime —
// a restart is the deploy mechanism (see M3's ASG instance refresh).
type config struct {
	Port               string
	DatabaseURL        string
	RedisAddr          string
	RedisAuthToken     string
	RedisTLS           bool
	RedisTLSServerName string
	S3Bucket           string
	S3Endpoint         string // set for LocalStack; empty in AWS, where the SDK resolves the real endpoint
	AWSRegion          string
	DrainTimeout       time.Duration
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
		username, password, err := fetchDBSecret(ctx, cfg.AWSRegion, arn)
		if err != nil {
			return cfg, fmt.Errorf("fetching DB secret %s: %w", arn, err)
		}
		dbHost := envOr("DB_HOST", "db.cloudforge.internal")
		dbName := envOr("DB_NAME", "cloudstore")
		dsn := url.URL{
			Scheme:   "postgres",
			User:     url.UserPassword(username, password),
			Host:     fmt.Sprintf("%s:5432", dbHost),
			Path:     "/" + dbName,
			RawQuery: "sslmode=require",
		}
		cfg.DatabaseURL = dsn.String()
	} else {
		cfg.DatabaseURL = envOr("DATABASE_URL", "postgres://cloudforge:cloudforge@localhost:5433/cloudforge?sslmode=disable")
	}

	if arn := os.Getenv("REDIS_AUTH_SECRET_ARN"); arn != "" {
		token, err := fetchRedisSecret(ctx, cfg.AWSRegion, arn)
		if err != nil {
			return cfg, fmt.Errorf("fetching Redis AUTH secret %s: %w", arn, err)
		}
		cfg.RedisAuthToken = token
		cfg.RedisTLS = true
		// ElastiCache's certificate is issued for its own generated hostname,
		// not our cache.cloudforge.internal CNAME (ADR-013) - TLS hostname
		// verification needs the real name even though we still dial the
		// friendly one via RedisAddr.
		cfg.RedisTLSServerName = os.Getenv("REDIS_TLS_SERVER_NAME")
	}

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// fetchDBSecret reads the AWS-managed master-user credentials out of
// Secrets Manager (ADR-009). The secret itself is just {"username",
// "password"} - RDS doesn't include host/port/dbname in it, so those come
// from DB_HOST/DB_NAME (or their defaults, matching ADR-013's private zone
// and the database module's db_name) to build the actual DSN. Only used in
// deployed environments (DB_SECRET_ARN set) — local dev passes DATABASE_URL
// directly, since there's no Secrets Manager to talk to.
func fetchDBSecret(ctx context.Context, region, arn string) (username, password string, err error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return "", "", err
	}
	client := secretsmanager.NewFromConfig(awsCfg)
	out, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(arn),
	})
	if err != nil {
		return "", "", err
	}

	var secret struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.Unmarshal([]byte(aws.ToString(out.SecretString)), &secret); err != nil {
		return "", "", fmt.Errorf("parsing secret JSON: %w", err)
	}
	return secret.Username, secret.Password, nil
}

// fetchRedisSecret reads the ElastiCache AUTH token out of Secrets Manager
// (M6). Unlike the RDS-managed secret above, this shape ({"auth_token":
// "..."}) isn't AWS-imposed - modules/cache creates it, so we chose the
// field name ourselves.
func fetchRedisSecret(ctx context.Context, region, arn string) (authToken string, err error) {
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

	var secret struct {
		AuthToken string `json:"auth_token"`
	}
	if err := json.Unmarshal([]byte(aws.ToString(out.SecretString)), &secret); err != nil {
		return "", fmt.Errorf("parsing secret JSON: %w", err)
	}
	return secret.AuthToken, nil
}
