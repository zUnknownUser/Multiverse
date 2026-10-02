-- Local-only settings are not consent to publish an existing diary.
ALTER TABLE profiles ADD COLUMN public_diary boolean NOT NULL DEFAULT false;
ALTER TABLE reviews ADD COLUMN moderation_status text NOT NULL DEFAULT 'visible'
  CHECK (moderation_status IN ('visible','hidden'));
CREATE INDEX reviews_feed_idx ON reviews(created_at DESC,id DESC);
CREATE INDEX reviews_author_feed_idx ON reviews(firebase_uid,created_at DESC,id DESC);
CREATE TABLE user_blocks (
  blocker_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  blocked_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(blocker_uid,blocked_uid),
  CHECK(blocker_uid<>blocked_uid)
);
CREATE INDEX user_blocks_reverse_idx ON user_blocks(blocked_uid,blocker_uid);
CREATE VIEW visible_follows AS
SELECT f.* FROM follows f WHERE NOT EXISTS (
  SELECT 1 FROM user_blocks b WHERE
  (b.blocker_uid=f.follower_uid AND b.blocked_uid=f.followed_uid) OR
  (b.blocked_uid=f.follower_uid AND b.blocker_uid=f.followed_uid)
);
CREATE TABLE review_reports (
  reporter_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  review_id uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK(reason IN ('spoiler','offensive','spam','wrong_canon','other')),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','reviewed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(reporter_uid,review_id)
);
CREATE INDEX review_reports_queue_idx ON review_reports(status,created_at);
