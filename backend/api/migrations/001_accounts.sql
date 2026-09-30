CREATE TABLE profiles (
  firebase_uid varchar(128) PRIMARY KEY,
  username varchar(24) NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_.]{3,24}$'),
  display_name varchar(80) NOT NULL CHECK (length(btrim(display_name)) > 0),
  avatar_color char(7) NOT NULL CHECK (avatar_color ~ '^#[0-9A-Fa-f]{6}$'),
  bio varchar(160) NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deletion_requested_at timestamptz
);
CREATE TABLE onboarding (
  firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  universe_ids text[] NOT NULL DEFAULT '{}',
  seen_item_ids text[] NOT NULL DEFAULT '{}',
  followed_user_ids text[] NOT NULL DEFAULT '{}',
  step smallint NOT NULL DEFAULT 1 CHECK (step BETWEEN 1 AND 3),
  completed boolean NOT NULL DEFAULT false,
  version integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE follows (
  follower_uid varchar(128) REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  followed_uid varchar(128) REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_uid, followed_uid),
  CHECK (follower_uid <> followed_uid)
);
CREATE INDEX follows_followed_idx ON follows(followed_uid);
