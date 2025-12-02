-- Rollback: comments_add_fk_post_id

ALTER TABLE comments DROP CONSTRAINT IF EXISTS fk_comments_comment_post;
