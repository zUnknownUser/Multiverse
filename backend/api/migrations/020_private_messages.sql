CREATE TABLE dm_threads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_a varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 user_b varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 initiator varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 state text NOT NULL CHECK(state IN ('pending','accepted','declined')),
 sequence bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(user_a,user_b), CHECK(user_a COLLATE "C" < user_b COLLATE "C"),
 CHECK(initiator IN (user_a,user_b))
);
CREATE INDEX dm_threads_a_idx ON dm_threads(user_a,updated_at DESC,id DESC);
CREATE INDEX dm_threads_b_idx ON dm_threads(user_b,updated_at DESC,id DESC);
CREATE INDEX dm_threads_budget_idx ON dm_threads(initiator,created_at);
CREATE TABLE dm_messages (
 id uuid PRIMARY KEY,
 thread_id uuid NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
 sender_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 sequence bigint NOT NULL,
 kind text NOT NULL CHECK(kind IN ('text','workCard')),
 text text NOT NULL CHECK(char_length(text)<=2000),
 item_id varchar(120) REFERENCES catalog_items(id) ON DELETE SET NULL,
 spoiler boolean NOT NULL DEFAULT false,
 moderation_status text NOT NULL DEFAULT 'visible' CHECK(moderation_status IN ('visible','hidden')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(thread_id,sequence), CHECK(kind<>'text' OR length(btrim(text))>0)
);
CREATE INDEX dm_messages_budget_idx ON dm_messages(sender_uid,created_at);
CREATE TABLE dm_reads (
 thread_id uuid NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 sequence bigint NOT NULL DEFAULT 0,
 PRIMARY KEY(thread_id,firebase_uid)
);
CREATE TABLE dm_reports (
 reporter_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 message_id uuid NOT NULL REFERENCES dm_messages(id) ON DELETE CASCADE,
 reason text NOT NULL CHECK(reason IN ('spoiler','offensive','spam','wrong_canon','other')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','reviewed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(reporter_uid,message_id)
);
CREATE TABLE dm_revisions (
 firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 revision bigint NOT NULL DEFAULT 0
);
CREATE FUNCTION dm_changed(account varchar) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF account IS NULL THEN RETURN; END IF;
 INSERT INTO dm_revisions(firebase_uid,revision) SELECT firebase_uid,1 FROM profiles WHERE firebase_uid=account
 ON CONFLICT(firebase_uid) DO UPDATE SET revision=dm_revisions.revision+1;
 PERFORM pg_notify('multiverse_room_changed','dm:' || account);
END $$;
CREATE FUNCTION dm_thread_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t dm_threads;
BEGIN
 IF TG_TABLE_NAME='dm_threads' THEN t:=NEW;
 ELSE SELECT * INTO t FROM dm_threads WHERE id=coalesce(NEW.thread_id,OLD.thread_id); END IF;
 -- Deterministic order avoids opposite-direction sends deadlocking revisions.
 PERFORM dm_changed(t.user_a); PERFORM dm_changed(t.user_b);
 RETURN NULL;
END $$;
CREATE TRIGGER dm_thread_event AFTER INSERT OR UPDATE ON dm_threads FOR EACH ROW EXECUTE FUNCTION dm_thread_changed();
CREATE TRIGGER dm_message_event AFTER INSERT OR UPDATE OR DELETE ON dm_messages FOR EACH ROW EXECUTE FUNCTION dm_thread_changed();
CREATE TRIGGER dm_read_event AFTER INSERT OR UPDATE ON dm_reads FOR EACH ROW EXECUTE FUNCTION dm_thread_changed();
CREATE FUNCTION dm_block_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a varchar; b varchar;
BEGIN
 a:=coalesce(NEW.blocker_uid,OLD.blocker_uid); b:=coalesce(NEW.blocked_uid,OLD.blocked_uid);
 PERFORM dm_changed(least(a COLLATE "C",b COLLATE "C"));
 PERFORM dm_changed(greatest(a COLLATE "C",b COLLATE "C")); RETURN NULL;
END $$;
CREATE TRIGGER dm_block_event AFTER INSERT OR DELETE ON user_blocks FOR EACH ROW EXECUTE FUNCTION dm_block_changed();
ALTER TABLE notifications DROP CONSTRAINT notifications_kind_check;
ALTER TABLE notifications ADD CHECK(kind IN ('follow','comment','reaction','mention','reply','message'));
ALTER TABLE notifications DROP CONSTRAINT notifications_target_type_check;
ALTER TABLE notifications ADD CHECK(target_type IN ('person','review','post','message'));
ALTER TABLE moderation_decisions DROP CONSTRAINT moderation_decisions_target_type_check;
ALTER TABLE moderation_decisions ADD CHECK(target_type IN ('review','comment','post','post_comment','club','message'));
