-- Migration: post_categories_add_index_idx_post_categories_unique
-- Table: post_categories
-- Type: add_index

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_categories_unique ON post_categories (post_id, category_id);
