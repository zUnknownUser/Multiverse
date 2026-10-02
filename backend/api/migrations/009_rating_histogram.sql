-- Keep the average and distribution on the same rule: the latest positive
-- rating per person/work, excluding accounts pending deletion.
CREATE OR REPLACE VIEW catalog_item_statistics AS
WITH latest_ratings AS (
  SELECT DISTINCT ON (d.firebase_uid,d.item_id) d.item_id,d.rating
  FROM diary_entries d JOIN profiles p USING(firebase_uid)
  WHERE d.rating > 0 AND p.deletion_requested_at IS NULL
  ORDER BY d.firebase_uid,d.item_id,d.updated_at DESC,d.id
), ratings AS (
  SELECT item_id,avg(rating)::float AS average,
    ARRAY[
      count(*) FILTER (WHERE rating=0.5), count(*) FILTER (WHERE rating=1),
      count(*) FILTER (WHERE rating=1.5), count(*) FILTER (WHERE rating=2),
      count(*) FILTER (WHERE rating=2.5), count(*) FILTER (WHERE rating=3),
      count(*) FILTER (WHERE rating=3.5), count(*) FILTER (WHERE rating=4),
      count(*) FILTER (WHERE rating=4.5), count(*) FILTER (WHERE rating=5)
    ]::int[] AS histogram
  FROM latest_ratings GROUP BY item_id
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
  coalesce(rc.count,0)::int AS review_count,
  coalesce(r.histogram,ARRAY[0,0,0,0,0,0,0,0,0,0]) AS rating_histogram
FROM catalog_items i LEFT JOIN ratings r ON r.item_id=i.id LEFT JOIN logs l ON l.item_id=i.id
LEFT JOIN review_counts rc ON rc.item_id=i.id;
