-- Migration: post_categories_add_fk_category_id
-- Table: post_categories
-- Type: add_foreign_key

ALTER TABLE post_categories ADD CONSTRAINT fk_post_categories_junction_category
  FOREIGN KEY (category_id) REFERENCES categories(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
