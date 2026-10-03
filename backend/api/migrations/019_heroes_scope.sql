-- Product scope is Marvel and DC. Archive retired catalog records rather than
-- deleting user-owned history or breaking foreign keys from older installations.
UPDATE catalog_universes SET status='archived' WHERE id NOT IN ('marvel','dc');
UPDATE catalog_items SET status='archived' WHERE universe_id NOT IN ('marvel','dc');

-- Preserve valid choices and their order. A stale device must refetch the new
-- version before writing its old preferences back. Finished accounts stay finished.
WITH scoped AS (
  SELECT o.firebase_uid,
    ARRAY(SELECT id FROM unnest(o.universe_ids) WITH ORDINALITY AS u(id,n)
      WHERE id IN ('marvel','dc') ORDER BY n) AS universes,
    ARRAY(SELECT id FROM unnest(o.seen_item_ids) WITH ORDINALITY AS s(id,n)
      WHERE EXISTS(SELECT 1 FROM catalog_items i WHERE i.id=s.id AND i.universe_id IN ('marvel','dc'))
      ORDER BY n) AS items
  FROM onboarding o
)
UPDATE onboarding o SET universe_ids=s.universes,seen_item_ids=s.items,
  step=CASE WHEN NOT o.completed AND cardinality(s.universes)=0 THEN 1 ELSE o.step END,
  version=o.version+1,updated_at=now()
FROM scoped s WHERE o.firebase_uid=s.firebase_uid
  AND (o.universe_ids IS DISTINCT FROM s.universes OR o.seen_item_ids IS DISTINCT FROM s.items);
