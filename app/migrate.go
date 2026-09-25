package main

import (
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/golang-migrate/migrate/v4"
	migratepgx "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	_ "github.com/jackc/pgx/v5/stdlib" // registers the "pgx" database/sql driver
)

// The SQL files are compiled into the binary, so a deployed instance needs
// nothing but the binary itself to bring a fresh database up to date.
//
//go:embed migrations/*.sql
var migrationFiles embed.FS

const (
	migrateAttempts = 12
	migrateBackoff  = 5 * time.Second
)

// migrateWithRetry runs the migrations before the app starts serving, and
// retries for about a minute if they fail. systemd restarts the service every
// 2s and gives up after 5 failed starts in 10s, so exiting on the first
// failure (a database that isn't accepting connections yet) would leave the
// service stopped for good instead of waiting for it.
func migrateWithRetry(dsn string, log *slog.Logger) (uint, error) {
	for attempt := 1; ; attempt++ {
		version, err := runMigrations(dsn)
		if err == nil {
			return version, nil
		}
		if attempt == migrateAttempts {
			return 0, err
		}
		log.Warn("migrations failed, retrying", "attempt", attempt, "error", err)
		time.Sleep(migrateBackoff)
	}
}

// runMigrations applies every pending migration and returns the schema
// version the database is at afterwards. The pgx driver holds a Postgres
// advisory lock while it runs, so several instances booting at once (an ASG
// launching two) take turns instead of racing: the first applies the
// migrations, the rest find nothing left to do.
func runMigrations(dsn string) (uint, error) {
	src, err := iofs.New(migrationFiles, "migrations")
	if err != nil {
		return 0, fmt.Errorf("reading embedded migrations: %w", err)
	}

	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return 0, err
	}
	driver, err := migratepgx.WithInstance(db, &migratepgx.Config{})
	if err != nil {
		db.Close()
		return 0, fmt.Errorf("connecting for migrations: %w", err)
	}

	m, err := migrate.NewWithInstance("iofs", src, "pgx5", driver)
	if err != nil {
		driver.Close()
		return 0, err
	}
	defer m.Close()

	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return 0, fmt.Errorf("applying migrations: %w", err)
	}
	version, _, err := m.Version()
	return version, err
}
