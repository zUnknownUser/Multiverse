ALTER TABLE account_deletions ADD COLUMN last_attempt_at timestamptz;
DROP INDEX account_deletions_pending_idx;
CREATE INDEX account_deletions_pending_idx
ON account_deletions(last_attempt_at NULLS FIRST, requested_at, firebase_uid)
WHERE completed_at IS NULL;
