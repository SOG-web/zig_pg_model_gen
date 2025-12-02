-- Migration: categories_add_index_idx_categories_slug
-- Table: categories
-- Type: add_index

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_slug ON categories (slug);
