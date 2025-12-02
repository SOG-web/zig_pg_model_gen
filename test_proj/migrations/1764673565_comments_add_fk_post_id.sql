-- Migration: comments_add_fk_post_id
-- Table: comments
-- Type: add_foreign_key

ALTER TABLE comments ADD CONSTRAINT fk_comments_comment_post
  FOREIGN KEY (post_id) REFERENCES posts(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
