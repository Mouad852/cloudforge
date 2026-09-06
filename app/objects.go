package main

import (
	"bytes"
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type objectStore struct {
	client *s3.Client
	bucket string
}

func newObjectStore(ctx context.Context, cfg config) (*objectStore, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(cfg.AWSRegion))
	if err != nil {
		return nil, err
	}

	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		if cfg.S3Endpoint != "" {
			// LocalStack: path-style, explicit endpoint override.
			o.BaseEndpoint = aws.String(cfg.S3Endpoint)
			o.UsePathStyle = true
		}
	})

	return &objectStore{client: client, bucket: cfg.S3Bucket}, nil
}

// put uploads a product image and returns the S3 key it was stored under.
func (o *objectStore) put(ctx context.Context, productID string, contentType string, body []byte) (string, error) {
	key := fmt.Sprintf("products/%s", productID)
	_, err := o.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(o.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(body),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", err
	}
	return key, nil
}
