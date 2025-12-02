-- Migration: posts_add_fk_user_id
-- Table: posts
-- Type: add_foreign_key

ALTER TABLE posts ADD CONSTRAINT fk_posts_post_author
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
