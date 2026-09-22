package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
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

// get streams a product image back out of S3, along with its stored content
// type. The caller must close the returned reader.
//
// This exists because /images/* used to be served straight out of the
// bucket through CloudFront's Origin Access Control (M6); with no
// CloudFront (ADR-025), the app reads the object itself using the same
// s3:GetObject permission it already had on this bucket, rather than
// making the bucket public or handing out presigned URLs - both of which
// would let image traffic skip the WAF and the rate limit.
func (o *objectStore) get(ctx context.Context, key string) (io.ReadCloser, string, error) {
	out, err := o.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(o.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		var nsk *types.NoSuchKey
		if errors.As(err, &nsk) {
			return nil, "", ErrNotFound
		}
		return nil, "", err
	}
	return out.Body, aws.ToString(out.ContentType), nil
}
