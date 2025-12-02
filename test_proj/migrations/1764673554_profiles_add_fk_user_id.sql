-- Migration: profiles_add_fk_user_id
-- Table: profiles
-- Type: add_foreign_key

ALTER TABLE profiles ADD CONSTRAINT fk_profiles_profile_user
  FOREIGN KEY (user_id) REFERENCES users(id)
  ON DELETE CASCADE ON UPDATE NO ACTION;
