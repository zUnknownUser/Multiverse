CREATE TABLE profile_photos (
 firebase_uid text PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 id uuid NOT NULL UNIQUE,
 bytes bytea NOT NULL CHECK (octet_length(bytes) <= 262144),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE profiles ADD COLUMN avatar_photo_id uuid REFERENCES profile_photos(id) ON DELETE SET NULL;
