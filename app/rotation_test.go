package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/jackc/pgx/v5"
)

// fakeSecrets serves the RDS-managed secret's JSON with whatever password the
// test sets, the way Secrets Manager does before and after a rotation.
type fakeSecrets struct{ password string }

func (f *fakeSecrets) GetSecretValue(_ context.Context, _ *secretsmanager.GetSecretValueInput, _ ...func(*secretsmanager.Options)) (*secretsmanager.GetSecretValueOutput, error) {
	b, _ := json.Marshal(map[string]string{"username": "cloudforge", "password": f.password})
	return &secretsmanager.GetSecretValueOutput{SecretString: aws.String(string(b))}, nil
}

// The 2026-09-30 outage: the password rotated, and connections opened after
// that still used the one read at boot. A connection opened after a rotation
// must log in with the new password.
func TestNewConnectionsUseTheRotatedPassword(t *testing.T) {
	secrets := &fakeSecrets{password: "before-rotation"}
	password := func(ctx context.Context) (string, error) {
		_, p, err := fetchDBSecret(ctx, secrets, "arn:test")
		return p, err
	}

	// The pool connects lazily, so no database is needed to build it.
	st, err := newStore(context.Background(), "postgres://cloudforge:before-rotation@127.0.0.1:1/cloudstore", password)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(st.Close)
	beforeConnect := st.pool.Config().BeforeConnect
	if beforeConnect == nil {
		t.Fatal("the pool has no BeforeConnect hook, so it would reuse the boot-time password")
	}

	secrets.password = "after-rotation"
	cc := &pgx.ConnConfig{}
	if err := beforeConnect(context.Background(), cc); err != nil {
		t.Fatal(err)
	}
	if cc.Password != "after-rotation" {
		t.Fatalf("new connection would log in with %q, want the rotated password", cc.Password)
	}
}

func TestPasswordLookupFailureStopsTheConnection(t *testing.T) {
	st, err := newStore(context.Background(), "postgres://u:p@127.0.0.1:1/db", func(context.Context) (string, error) {
		return "", errors.New("secrets manager unreachable")
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(st.Close)

	if err := st.pool.Config().BeforeConnect(context.Background(), &pgx.ConnConfig{}); err == nil {
		t.Fatal("a failed password lookup must fail the connection, not connect with a stale password")
	}
}

// Local dev passes no password function: the DSN's password is used as is.
func TestLocalDevKeepsTheDSNPassword(t *testing.T) {
	st, err := newStore(context.Background(), "postgres://u:p@127.0.0.1:1/db", nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(st.Close)

	if st.pool.Config().BeforeConnect != nil {
		t.Fatal("no password function was given, so no hook should be set")
	}
}

func TestServerErrorsLogTheirCause(t *testing.T) {
	var out bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&out, nil))
	h := withRequestLogging(log, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusInternalServerError, errors.New("password authentication failed"))
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/products", nil))

	if !strings.Contains(out.String(), "password authentication failed") {
		t.Fatalf("5xx log line does not carry the error: %s", out.String())
	}
}

func TestClientErrorsDoNotLogTheirBody(t *testing.T) {
	var out bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&out, nil))
	h := withRequestLogging(log, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusBadRequest, errors.New("name is required"))
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/api/products", nil))

	if strings.Contains(out.String(), "name is required") {
		t.Fatalf("4xx bodies are the client's problem and should stay out of the log: %s", out.String())
	}
}
