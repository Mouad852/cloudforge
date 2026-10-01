package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("product not found")

type Product struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	PriceCents int       `json:"price_cents"`
	ImageKey   *string   `json:"image_key,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type store struct {
	pool *pgxpool.Pool
}

// newStore opens the connection pool. With a password function (deployed
// environments), every new connection asks it for the current password
// instead of reusing the one read at boot. Until M10 it did reuse it: after
// Secrets Manager rotated the password on 2026-09-30, each connection the pool
// opened was refused, and prod's API returned 500 for about 40 hours, until
// the next deploy restarted the app (docs/incidents/2026-09-30-db-password-rotation.md).
func newStore(ctx context.Context, dsn string, password func(context.Context) (string, error)) (*store, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	if password != nil {
		cfg.BeforeConnect = func(ctx context.Context, cc *pgx.ConnConfig) error {
			p, err := password(ctx)
			if err != nil {
				return fmt.Errorf("reading the current database password: %w", err)
			}
			cc.Password = p
			return nil
		}
	}

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return &store{pool: pool}, nil
}

func (s *store) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

func (s *store) Close() {
	s.pool.Close()
}

func (s *store) List(ctx context.Context) ([]Product, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, name, price_cents, image_key, created_at FROM products ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	products := []Product{}
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.Name, &p.PriceCents, &p.ImageKey, &p.CreatedAt); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, rows.Err()
}

func (s *store) Get(ctx context.Context, id string) (Product, error) {
	var p Product
	err := s.pool.QueryRow(ctx,
		`SELECT id, name, price_cents, image_key, created_at FROM products WHERE id = $1`, id,
	).Scan(&p.ID, &p.Name, &p.PriceCents, &p.ImageKey, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, ErrNotFound
	}
	return p, err
}

func (s *store) Create(ctx context.Context, name string, priceCents int) (Product, error) {
	var p Product
	err := s.pool.QueryRow(ctx,
		`INSERT INTO products (name, price_cents) VALUES ($1, $2)
		 RETURNING id, name, price_cents, image_key, created_at`,
		name, priceCents,
	).Scan(&p.ID, &p.Name, &p.PriceCents, &p.ImageKey, &p.CreatedAt)
	return p, err
}

func (s *store) Delete(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM products WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *store) SetImageKey(ctx context.Context, id, key string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE products SET image_key = $1 WHERE id = $2`, key, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
