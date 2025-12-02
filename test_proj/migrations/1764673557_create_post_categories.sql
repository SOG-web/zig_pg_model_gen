-- Migration: create_post_categories
-- Table: post_categories
-- Type: create_table

CREATE TABLE IF NOT EXISTS post_categories (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL,
  category_id UUID NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
