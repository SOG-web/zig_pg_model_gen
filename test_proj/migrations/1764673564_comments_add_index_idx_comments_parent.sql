-- Migration: comments_add_index_idx_comments_parent
-- Table: comments
-- Type: add_index

CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments (parent_id);
