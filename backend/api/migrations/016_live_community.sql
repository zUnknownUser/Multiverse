CREATE TABLE community_clubs (
 id uuid PRIMARY KEY,
 owner_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 universe_id text NOT NULL REFERENCES catalog_universes(id),
 name text NOT NULL CHECK(char_length(name) BETWEEN 1 AND 80),
 description text NOT NULL CHECK(char_length(description) BETWEEN 1 AND 1000),
 moderation_status text NOT NULL DEFAULT 'visible' CHECK(moderation_status IN ('visible','hidden')),
 version integer NOT NULL DEFAULT 1,
 deleted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE club_members (
 club_id uuid NOT NULL REFERENCES community_clubs(id) ON DELETE CASCADE,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 joined_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(club_id,firebase_uid)
);
CREATE TABLE club_schedule (
 id uuid PRIMARY KEY,
 club_id uuid NOT NULL REFERENCES community_clubs(id) ON DELETE CASCADE,
 item_id text NOT NULL REFERENCES catalog_items(id),
 starts_on date NOT NULL,
 total_units integer NOT NULL CHECK(total_units BETWEEN 1 AND 10000),
 unit_label text NOT NULL CHECK(char_length(unit_label) BETWEEN 1 AND 30),
 UNIQUE(id,club_id), UNIQUE(club_id,starts_on)
);
CREATE TABLE club_progress (
 schedule_id uuid NOT NULL REFERENCES club_schedule(id) ON DELETE CASCADE,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 units integer NOT NULL CHECK(units>=0),
 PRIMARY KEY(schedule_id,firebase_uid)
);
ALTER TABLE community_posts ADD COLUMN kind text NOT NULL DEFAULT 'discussion' CHECK(kind IN ('discussion','theory','duel','room'));
ALTER TABLE community_posts ADD COLUMN club_id uuid REFERENCES community_clubs(id) ON DELETE CASCADE;
ALTER TABLE community_posts ADD COLUMN schedule_id uuid;
ALTER TABLE community_posts ADD FOREIGN KEY(schedule_id,club_id) REFERENCES club_schedule(id,club_id) ON DELETE CASCADE;
ALTER TABLE community_posts ADD COLUMN segment smallint NOT NULL DEFAULT 0 CHECK(segment BETWEEN 0 AND 2);
ALTER TABLE community_posts ADD COLUMN version integer NOT NULL DEFAULT 1;
ALTER TABLE community_posts ADD COLUMN edited_at timestamptz;
ALTER TABLE community_posts ADD COLUMN edit_id uuid;
ALTER TABLE community_posts ADD COLUMN option_a text CHECK(char_length(option_a) BETWEEN 1 AND 120);
ALTER TABLE community_posts ADD COLUMN option_b text CHECK(char_length(option_b) BETWEEN 1 AND 120);
ALTER TABLE community_posts ADD COLUMN closes_at timestamptz;
ALTER TABLE community_posts ADD COLUMN resolution text NOT NULL DEFAULT 'open' CHECK(resolution IN ('open','confirmed','refuted'));
ALTER TABLE community_posts ADD COLUMN resolution_note text CHECK(char_length(resolution_note) BETWEEN 1 AND 1000);
ALTER TABLE community_posts ADD CHECK(kind<>'duel' OR (option_a IS NOT NULL AND option_b IS NOT NULL AND option_a<>option_b AND closes_at IS NOT NULL));
ALTER TABLE community_posts ADD CHECK(kind<>'room' OR item_id IS NOT NULL);
ALTER TABLE community_posts ADD CHECK(schedule_id IS NULL OR club_id IS NOT NULL);
CREATE INDEX community_posts_club_idx ON community_posts(club_id,created_at DESC,id DESC);
CREATE INDEX community_posts_kind_idx ON community_posts(kind,created_at DESC,id DESC);
CREATE INDEX community_posts_search_idx ON community_posts USING gin(to_tsvector('simple',title || ' ' || text));
ALTER TABLE post_comments ADD COLUMN parent_id uuid;
ALTER TABLE post_comments ADD FOREIGN KEY(parent_id,post_id) REFERENCES post_comments(id,post_id) ON DELETE CASCADE;
ALTER TABLE post_comments ADD CHECK(parent_id IS NULL OR parent_id<>id);
CREATE INDEX post_comments_parent_idx ON post_comments(parent_id,created_at,id);
CREATE TABLE community_votes (
 post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 choice smallint NOT NULL CHECK(choice IN (0,1)),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(post_id,firebase_uid)
);
-- Draft images are private and expire after a day unless attached to a post.
-- Bytes are bounded JPEGs, never arbitrary external URLs or original metadata.
CREATE TABLE community_images (
 id uuid PRIMARY KEY,
 draft_post_id uuid NOT NULL,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 digest text NOT NULL,
 bytes bytea NOT NULL CHECK(octet_length(bytes) BETWEEN 1 AND 1048576),
 width integer NOT NULL CHECK(width BETWEEN 1 AND 1600),
 height integer NOT NULL CHECK(height BETWEEN 1 AND 1600),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX community_images_owner_idx ON community_images(firebase_uid,created_at);
CREATE TABLE post_images (
 image_id uuid PRIMARY KEY REFERENCES community_images(id) ON DELETE CASCADE,
 post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
 position smallint NOT NULL CHECK(position BETWEEN 0 AND 3),
 UNIQUE(post_id,position)
);
CREATE TABLE community_mentions (
 post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
 comment_id uuid,
 recipient_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 FOREIGN KEY(comment_id,post_id) REFERENCES post_comments(id,post_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX community_mentions_unique ON community_mentions(post_id,coalesce(comment_id,'00000000-0000-0000-0000-000000000000'::uuid),recipient_uid);
ALTER TABLE notifications DROP CONSTRAINT notifications_kind_check;
ALTER TABLE notifications ADD CHECK(kind IN ('follow','comment','reaction','mention','reply'));
CREATE TABLE room_visits (
 item_id text NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 progress integer NOT NULL DEFAULT 0 CHECK(progress BETWEEN 0 AND 100),
 seen_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(item_id,firebase_uid)
);

CREATE TABLE club_reports (
 reporter_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 club_id uuid NOT NULL REFERENCES community_clubs(id) ON DELETE CASCADE,
 reason text NOT NULL CHECK(reason IN ('spoiler','offensive','spam','wrong_canon','other')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','reviewed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(reporter_uid,club_id)
);
ALTER TABLE moderation_decisions DROP CONSTRAINT moderation_decisions_target_type_check;
ALTER TABLE moderation_decisions ADD CHECK(target_type IN ('review','comment','post','post_comment','club'));
