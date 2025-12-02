-- Migration: create_comments
-- Table: comments
-- Type: create_table

CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL,
  user_id UUID NOT NULL,
  parent_id UUID,
  content TEXT NOT NULL,
  is_approved BOOLEAN NOT NULL DEFAULT true,
  like_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP
);
