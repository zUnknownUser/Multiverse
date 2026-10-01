CREATE TABLE diary_entries (
  firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
  id uuid NOT NULL,
  item_id varchar(80) NOT NULL REFERENCES catalog_items(id),
  logged_at timestamptz NOT NULL,
  rating double precision NOT NULL CHECK (rating >= 0 AND rating <= 5 AND rating * 2 = floor(rating * 2)),
  liked boolean NOT NULL DEFAULT false,
  rewatch boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (firebase_uid,id)
);
CREATE INDEX diary_entries_owner_date_idx ON diary_entries(firebase_uid,logged_at DESC,id);
CREATE INDEX diary_entries_item_idx ON diary_entries(item_id);
CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid varchar(128) NOT NULL,
  entry_id uuid NOT NULL,
  text text NOT NULL DEFAULT '' CHECK (length(text) <= 5000),
  spoiler boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(firebase_uid,entry_id),
  FOREIGN KEY (firebase_uid,entry_id) REFERENCES diary_entries(firebase_uid,id) ON DELETE CASCADE
);

-- One person's repeat visits must not multiply their weight in the average.
CREATE VIEW catalog_item_statistics AS
WITH latest_ratings AS (
  SELECT DISTINCT ON (d.firebase_uid,d.item_id) d.item_id,d.rating
  FROM diary_entries d JOIN profiles p USING(firebase_uid)
  WHERE d.rating > 0 AND p.deletion_requested_at IS NULL
  ORDER BY d.firebase_uid,d.item_id,d.updated_at DESC,d.id
), ratings AS (
  SELECT item_id,avg(rating)::float AS average FROM latest_ratings GROUP BY item_id
), logs AS (
  SELECT item_id,count(*)::int AS count FROM diary_entries d JOIN profiles p USING(firebase_uid)
  WHERE p.deletion_requested_at IS NULL GROUP BY item_id
), review_counts AS (
  SELECT d.item_id,count(*)::int AS count FROM reviews r
  JOIN diary_entries d ON d.firebase_uid=r.firebase_uid AND d.id=r.entry_id
  JOIN profiles p ON p.firebase_uid=r.firebase_uid
  WHERE p.deletion_requested_at IS NULL GROUP BY d.item_id
)
SELECT i.id AS item_id,coalesce(r.average,0)::float AS average,coalesce(l.count,0)::int AS log_count,
  coalesce(rc.count,0)::int AS review_count
FROM catalog_items i LEFT JOIN ratings r ON r.item_id=i.id LEFT JOIN logs l ON l.item_id=i.id
LEFT JOIN review_counts rc ON rc.item_id=i.id;
