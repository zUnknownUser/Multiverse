-- Independent of profiles: deletion must remain durable before profile creation
-- and after profile removal, including already-authenticated requests in flight.
CREATE TABLE account_deletions (
  firebase_uid varchar(128) PRIMARY KEY,
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
INSERT INTO account_deletions(firebase_uid, requested_at)
SELECT firebase_uid, deletion_requested_at FROM profiles
WHERE deletion_requested_at IS NOT NULL;
CREATE INDEX account_deletions_pending_idx ON account_deletions(requested_at)
WHERE completed_at IS NULL;
