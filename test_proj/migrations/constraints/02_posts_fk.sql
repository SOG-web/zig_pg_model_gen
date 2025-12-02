-- Foreign Key Constraints for: posts
ALTER TABLE posts ADD CONSTRAINT fk_posts_post_author
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;