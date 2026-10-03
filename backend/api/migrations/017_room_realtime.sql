-- Durable revision catches notifications missed during disconnects. Notifications
-- contain only the room key; every content read retains its authorization checks.
CREATE TABLE room_revisions (
 item_id text PRIMARY KEY REFERENCES catalog_items(id) ON DELETE CASCADE,
 revision bigint NOT NULL DEFAULT 1
);
CREATE FUNCTION notify_room_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE room text;
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.kind='room' THEN room := OLD.item_id; END IF;
 ELSE
  IF NEW.kind='room' THEN room := NEW.item_id; END IF;
 END IF;
 IF room IS NOT NULL AND EXISTS(SELECT 1 FROM catalog_items WHERE id=room) THEN
  INSERT INTO room_revisions(item_id,revision) VALUES(room,1)
  ON CONFLICT(item_id) DO UPDATE SET revision=room_revisions.revision+1;
  PERFORM pg_notify('multiverse_room_changed',room);
 END IF;
 RETURN NULL;
END;
$$;
CREATE TRIGGER community_posts_room_change
AFTER INSERT OR UPDATE OR DELETE ON community_posts
FOR EACH ROW EXECUTE FUNCTION notify_room_change();
