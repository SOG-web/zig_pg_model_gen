-- Foreign Key Constraints for: post_categories
ALTER TABLE post_categories ADD CONSTRAINT fk_post_categories_junction_post
  FOREIGN KEY (post_id) REFERENCES posts(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE post_categories ADD CONSTRAINT fk_post_categories_junction_category
  FOREIGN KEY (category_id) REFERENCES categories(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;