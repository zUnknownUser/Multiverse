CREATE TABLE community_posts (
 id uuid PRIMARY KEY,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 universe_id text NOT NULL REFERENCES catalog_universes(id),
 item_id text REFERENCES catalog_items(id),
 title text NOT NULL CHECK(char_length(title) BETWEEN 1 AND 140),
 text text NOT NULL CHECK(char_length(text) BETWEEN 1 AND 5000),
 spoiler boolean NOT NULL DEFAULT false,
 moderation_status text NOT NULL DEFAULT 'visible' CHECK(moderation_status IN ('visible','hidden')),
 deleted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX community_posts_feed_idx ON community_posts(created_at DESC,id DESC);
CREATE INDEX community_posts_universe_idx ON community_posts(universe_id,created_at DESC,id DESC);
CREATE INDEX community_posts_item_idx ON community_posts(item_id,created_at DESC,id DESC);
CREATE INDEX community_posts_author_idx ON community_posts(firebase_uid,created_at);
CREATE TABLE post_comments (
 id uuid PRIMARY KEY,
 post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 text text NOT NULL CHECK(char_length(text) BETWEEN 1 AND 2000),
 spoiler boolean NOT NULL DEFAULT false,
 moderation_status text NOT NULL DEFAULT 'visible' CHECK(moderation_status IN ('visible','hidden')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(id,post_id)
);
CREATE INDEX post_comments_page_idx ON post_comments(post_id,created_at,id);
CREATE INDEX post_comments_author_idx ON post_comments(firebase_uid,created_at);
CREATE TABLE post_reactions (
 target_id uuid NOT NULL,
 post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
 comment_id uuid,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 reaction text CHECK(reaction IN ('POW!','ZAP!','KRAK!','HEH')),
 liked boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(target_id,firebase_uid),
 FOREIGN KEY(comment_id,post_id) REFERENCES post_comments(id,post_id) ON DELETE CASCADE,
 CHECK(target_id=coalesce(comment_id,post_id))
);
CREATE TABLE post_reports (
 reporter_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 post_id uuid NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
 reason text NOT NULL CHECK(reason IN ('spoiler','offensive','spam','wrong_canon','other')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','reviewed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(reporter_uid,post_id)
);
CREATE TABLE post_comment_reports (
 reporter_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 comment_id uuid NOT NULL REFERENCES post_comments(id) ON DELETE CASCADE,
 reason text NOT NULL CHECK(reason IN ('spoiler','offensive','spam','wrong_canon','other')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','reviewed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(reporter_uid,comment_id)
);
ALTER TABLE moderation_decisions DROP CONSTRAINT moderation_decisions_target_type_check;
ALTER TABLE moderation_decisions ADD CHECK(target_type IN ('review','comment','post','post_comment'));
CREATE TABLE notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 recipient_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 actor_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('follow','comment','reaction')),
 target_type text NOT NULL CHECK(target_type IN ('person','review','post')),
 target_id text NOT NULL,
 comment_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 read_at timestamptz,
 push_state text NOT NULL DEFAULT 'pending' CHECK(push_state IN ('pending','sent','skipped')),
 push_attempts integer NOT NULL DEFAULT 0,
 push_after timestamptz NOT NULL DEFAULT now(),
 CHECK(recipient_uid<>actor_uid)
);
CREATE UNIQUE INDEX notifications_dedupe_idx ON notifications(recipient_uid,actor_uid,kind,target_type,target_id,coalesce(comment_id,'00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX notifications_page_idx ON notifications(recipient_uid,created_at DESC,id DESC);
CREATE INDEX notifications_push_idx ON notifications(push_after) WHERE push_state='pending';
CREATE TABLE notification_preferences (
 firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 activity boolean NOT NULL DEFAULT true,
 push boolean NOT NULL DEFAULT false
);
-- Registration IDs are random per signed-in session, preventing a delayed logout from deleting another account's registration.
CREATE TABLE push_devices (
 id uuid PRIMARY KEY,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 token text UNIQUE NOT NULL CHECK(char_length(token) BETWEEN 20 AND 4096),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX push_devices_owner_idx ON push_devices(firebase_uid);
CREATE TABLE push_deliveries (
 notification_id uuid NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
 device_id uuid NOT NULL REFERENCES push_devices(id) ON DELETE CASCADE,
 PRIMARY KEY(notification_id,device_id)
);
