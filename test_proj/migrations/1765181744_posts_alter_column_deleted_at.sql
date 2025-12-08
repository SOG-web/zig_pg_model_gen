-- Migration: posts_alter_column_deleted_at
-- Table: posts
-- Type: alter_column

ALTER TABLE posts ALTER COLUMN deleted_at DROP DEFAULT;
