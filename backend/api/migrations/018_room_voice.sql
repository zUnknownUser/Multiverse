-- Keep leases after profile/catalog deletion so the media participant can still
-- be disconnected. UUID identity prevents a delayed cleanup kicking a new join.
CREATE TABLE room_voice_sessions (
 id uuid PRIMARY KEY,
 firebase_uid varchar(128) NOT NULL,
 item_id text NOT NULL,
 segment smallint NOT NULL CHECK(segment BETWEEN 0 AND 2),
 room_name text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '60 seconds',
 revoked_at timestamptz
);
CREATE UNIQUE INDEX room_voice_one_active ON room_voice_sessions(firebase_uid) WHERE revoked_at IS NULL;
CREATE INDEX room_voice_room ON room_voice_sessions(room_name) WHERE revoked_at IS NULL;
CREATE INDEX room_voice_expiry ON room_voice_sessions(expires_at);
CREATE TABLE room_voice_join_limits (
 firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 window_start timestamptz NOT NULL DEFAULT now(),
 attempts integer NOT NULL DEFAULT 1
);
