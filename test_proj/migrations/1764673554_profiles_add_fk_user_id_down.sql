-- Rollback: profiles_add_fk_user_id

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS fk_profiles_profile_user;
