-- Migration: comments_add_fk_user_id
-- Table: comments
-- Type: add_foreign_key

ALTER TABLE comments ADD CONSTRAINT fk_comments_comment_author
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
