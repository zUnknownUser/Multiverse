-- Publication receipts outlive the content, but never the account.
CREATE TABLE review_publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX review_publications_account_window ON review_publications(firebase_uid,created_at);
-- Preserve the remaining budget when upgrading an existing installation.
INSERT INTO review_publications(id,firebase_uid,created_at)
SELECT id,firebase_uid,created_at FROM reviews WHERE created_at>now()-interval '1 hour';

-- One durable counter per profile; failed image processing consumes an attempt.
CREATE TABLE profile_photo_limits (
  firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  window_start timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 20)
);
