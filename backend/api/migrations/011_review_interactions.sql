ALTER TABLE profiles ADD COLUMN comment_permission text NOT NULL DEFAULT 'following'
  CHECK (comment_permission IN ('everyone','following','nobody'));
CREATE TABLE review_comments (
  id uuid PRIMARY KEY,
  review_id uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  text text NOT NULL CHECK (char_length(text) BETWEEN 1 AND 2000),
  spoiler boolean NOT NULL DEFAULT false,
  moderation_status text NOT NULL DEFAULT 'visible' CHECK (moderation_status IN ('visible','hidden')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,review_id)
);
CREATE INDEX review_comments_page_idx ON review_comments(review_id,created_at,id);
CREATE INDEX review_comments_author_idx ON review_comments(firebase_uid,created_at);
CREATE TABLE social_reactions (
  target_id uuid NOT NULL,
  review_id uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  comment_id uuid,
  firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  reaction text CHECK (reaction IN ('POW!','ZAP!','KRAK!','HEH')),
  liked boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(target_id,firebase_uid),
  FOREIGN KEY(comment_id,review_id) REFERENCES review_comments(id,review_id) ON DELETE CASCADE,
  CHECK(target_id=coalesce(comment_id,review_id))
);
CREATE INDEX social_reactions_author_idx ON social_reactions(firebase_uid,updated_at);
CREATE TABLE social_reaction_limits (
  firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  requests integer NOT NULL CHECK(requests BETWEEN 1 AND 120)
);
CREATE TABLE comment_reports (
  reporter_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  comment_id uuid NOT NULL REFERENCES review_comments(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK(reason IN ('spoiler','offensive','spam','wrong_canon','other')),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','reviewed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(reporter_uid,comment_id)
);
CREATE INDEX comment_reports_queue_idx ON comment_reports(status,created_at);
-- Administrative decisions retain no copy of user text or reporter identity.
CREATE TABLE moderation_decisions (
  id uuid PRIMARY KEY,
  target_type text NOT NULL CHECK(target_type IN ('review','comment')),
  target_id uuid NOT NULL,
  action text NOT NULL CHECK(action IN ('hide','dismiss','restore')),
  operator text NOT NULL CHECK(char_length(operator) BETWEEN 1 AND 128),
  database_role text NOT NULL DEFAULT current_user,
  reason text NOT NULL CHECK(char_length(reason) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX moderation_decisions_target_idx ON moderation_decisions(target_type,target_id,created_at);
