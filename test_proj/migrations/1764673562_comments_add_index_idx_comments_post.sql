-- Migration: comments_add_index_idx_comments_post
-- Table: comments
-- Type: add_index

CREATE INDEX IF NOT EXISTS idx_comments_post ON comments (post_id);
