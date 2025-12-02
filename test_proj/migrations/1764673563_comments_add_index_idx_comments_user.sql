-- Migration: comments_add_index_idx_comments_user
-- Table: comments
-- Type: add_index

CREATE INDEX IF NOT EXISTS idx_comments_user ON comments (user_id);
