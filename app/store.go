package main

import (
	"context"
	"errors"
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

func newStore(ctx context.Context, dsn string) (*store, error) {
	pool, err := pgxpool.New(ctx, dsn)
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
