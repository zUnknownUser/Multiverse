ALTER TABLE profiles ADD COLUMN avatar_id text CHECK (avatar_id IN ('vigilant', 'cosmic', 'robot'));
