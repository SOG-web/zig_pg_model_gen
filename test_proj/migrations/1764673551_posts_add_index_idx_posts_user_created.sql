-- Migration: posts_add_index_idx_posts_user_created
-- Table: posts
-- Type: add_index

CREATE INDEX IF NOT EXISTS idx_posts_user_created ON posts (user_id, created_at);
