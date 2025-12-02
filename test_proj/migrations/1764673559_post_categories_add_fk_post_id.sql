-- Migration: post_categories_add_fk_post_id
-- Table: post_categories
-- Type: add_foreign_key

ALTER TABLE post_categories ADD CONSTRAINT fk_post_categories_junction_post
  FOREIGN KEY (post_id) REFERENCES posts(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
