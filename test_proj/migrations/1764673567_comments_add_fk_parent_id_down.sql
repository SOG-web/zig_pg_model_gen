-- Rollback: comments_add_fk_parent_id

ALTER TABLE comments DROP CONSTRAINT IF EXISTS fk_comments_comment_parent;
