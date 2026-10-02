// SQL expressions only; callers supply fixed aliases/placeholders, never user input.
export const unblocked = (viewer: string, target: string) => `NOT EXISTS (
  SELECT 1 FROM user_blocks b WHERE (b.blocker_uid=${viewer} AND b.blocked_uid=${target})
  OR (b.blocked_uid=${viewer} AND b.blocker_uid=${target}))`;

export const reviewRelations = `reviews r JOIN diary_entries d ON d.firebase_uid=r.firebase_uid AND d.id=r.entry_id
 JOIN profiles p ON p.firebase_uid=r.firebase_uid JOIN onboarding o ON o.firebase_uid=p.firebase_uid AND o.completed=true
 JOIN catalog_items ci ON ci.id=d.item_id AND ci.status='published'
 JOIN catalog_universes cu ON cu.id=ci.universe_id AND cu.status='active'`;
export const reviewVisible = `p.deletion_requested_at IS NULL AND (p.firebase_uid=$1 OR p.public_diary)
 AND r.moderation_status='visible' AND ${unblocked('$1', 'p.firebase_uid')}
 AND NOT EXISTS(SELECT 1 FROM review_reports rr WHERE rr.reporter_uid=$1 AND rr.review_id=r.id)`;
export const commentVisible = `c.moderation_status='visible' AND cp.deletion_requested_at IS NULL
 AND ${unblocked('$1', 'c.firebase_uid')} AND ${unblocked('r.firebase_uid', 'c.firebase_uid')}
 AND NOT EXISTS(SELECT 1 FROM comment_reports cr WHERE cr.reporter_uid=$1 AND cr.comment_id=c.id)`;
