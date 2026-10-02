CREATE TABLE library_state (
 firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 version integer NOT NULL DEFAULT 0 CHECK(version>=0),
 window_start timestamptz NOT NULL DEFAULT now(),
 requests integer NOT NULL DEFAULT 0 CHECK(requests BETWEEN 0 AND 120)
);
CREATE TABLE library_marks (
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 item_id text NOT NULL REFERENCES catalog_items(id),
 wanted boolean NOT NULL DEFAULT false,
 favorite boolean NOT NULL DEFAULT false,
 PRIMARY KEY(firebase_uid,item_id),
 CHECK(wanted OR favorite)
);
CREATE TABLE personal_lists (
 id uuid PRIMARY KEY,
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 title text NOT NULL CHECK(char_length(title) BETWEEN 1 AND 100),
 description text NOT NULL DEFAULT '' CHECK(char_length(description)<=1000),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX personal_lists_owner_idx ON personal_lists(firebase_uid,created_at,id);
CREATE TABLE personal_list_items (
 list_id uuid NOT NULL REFERENCES personal_lists(id) ON DELETE CASCADE,
 item_id text NOT NULL REFERENCES catalog_items(id),
 added_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(list_id,item_id)
);
-- Receipts preserve retries across deletion and other devices without resurrecting data.
CREATE TABLE library_mutations (
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 id uuid NOT NULL,
 request jsonb NOT NULL,
 applied_version integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(firebase_uid,id)
);
-- Preserve existing diary-derived favorites once. Future diary likes and library favorites are independent.
INSERT INTO library_marks(firebase_uid,item_id,favorite)
 SELECT firebase_uid,item_id,true FROM (
 SELECT DISTINCT ON(firebase_uid,item_id) firebase_uid,item_id,liked
 FROM diary_entries ORDER BY firebase_uid,item_id,logged_at DESC,id DESC
 ) latest WHERE liked;
