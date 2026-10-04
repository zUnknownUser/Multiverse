-- Daily editorial rounds reuse community votes/comments/moderation; no fake votes.
CREATE TABLE daily_duels (
 day date PRIMARY KEY,
 post_id uuid NOT NULL UNIQUE REFERENCES community_posts(id) ON DELETE CASCADE,
 translations jsonb NOT NULL CHECK(jsonb_typeof(translations)='object'),
 opens_at timestamptz NOT NULL,
 CHECK(opens_at=(day::timestamp AT TIME ZONE 'UTC'))
);
CREATE INDEX community_votes_participant_idx ON community_votes(firebase_uid,post_id);
