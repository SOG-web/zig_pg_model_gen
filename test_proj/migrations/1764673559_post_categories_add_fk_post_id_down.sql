-- Rollback: post_categories_add_fk_post_id

ALTER TABLE post_categories DROP CONSTRAINT IF EXISTS fk_post_categories_junction_post;
