-- Table: post_categories
CREATE TABLE IF NOT EXISTS post_categories (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL,
  category_id UUID NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_categories_unique ON post_categories (post_id, category_id);