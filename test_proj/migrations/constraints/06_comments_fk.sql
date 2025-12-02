-- Foreign Key Constraints for: comments
ALTER TABLE comments ADD CONSTRAINT fk_comments_comment_post
  FOREIGN KEY (post_id) REFERENCES posts(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE comments ADD CONSTRAINT fk_comments_comment_author
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
ALTER TABLE comments ADD CONSTRAINT fk_comments_comment_parent
  FOREIGN KEY (parent_id) REFERENCES comments(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;