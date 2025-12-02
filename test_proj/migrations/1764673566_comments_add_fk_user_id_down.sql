-- Rollback: comments_add_fk_user_id

ALTER TABLE comments DROP CONSTRAINT IF EXISTS fk_comments_comment_author;
