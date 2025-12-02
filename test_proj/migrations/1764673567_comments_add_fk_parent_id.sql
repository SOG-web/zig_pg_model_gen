-- Migration: comments_add_fk_parent_id
-- Table: comments
-- Type: add_foreign_key

ALTER TABLE comments ADD CONSTRAINT fk_comments_comment_parent
  FOREIGN KEY (parent_id) REFERENCES comments(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
