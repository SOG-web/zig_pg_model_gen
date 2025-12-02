-- Rollback: posts_add_fk_user_id

ALTER TABLE posts DROP CONSTRAINT IF EXISTS fk_posts_post_author;
