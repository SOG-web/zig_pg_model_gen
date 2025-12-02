-- Foreign Key Constraints for: profiles
ALTER TABLE profiles ADD CONSTRAINT fk_profiles_profile_user
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;