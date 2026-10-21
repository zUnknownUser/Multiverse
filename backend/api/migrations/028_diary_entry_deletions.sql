-- Retain identity, never review content, so a delayed PUT cannot resurrect a log.
CREATE TABLE diary_entry_deletions (
  firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  id uuid NOT NULL,
  item_id varchar(80) NOT NULL REFERENCES catalog_items(id),
  deleted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (firebase_uid,id)
);
