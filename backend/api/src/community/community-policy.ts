import { unblocked, commentVisible } from '../social/social-policy.js';
export const postRelations = `community_posts r JOIN profiles p ON p.firebase_uid=r.firebase_uid
 JOIN onboarding o ON o.firebase_uid=p.firebase_uid AND o.completed=true
 JOIN catalog_universes cu ON cu.id=r.universe_id AND cu.status='active'`;
export const postVisible = `p.deletion_requested_at IS NULL AND r.deleted_at IS NULL AND r.moderation_status='visible'
 AND (r.item_id IS NULL OR EXISTS(SELECT 1 FROM catalog_items ci WHERE ci.id=r.item_id AND ci.universe_id=r.universe_id AND ci.status='published'))
 AND ${unblocked('$1', 'r.firebase_uid')}
 AND (r.kind<>'room' OR r.segment=0 OR EXISTS(SELECT 1 FROM room_visits rv WHERE rv.item_id=r.item_id AND rv.firebase_uid=$1 AND rv.progress>=r.segment*50))
 AND (r.club_id IS NULL OR EXISTS(SELECT 1 FROM community_clubs cl JOIN profiles cop ON cop.firebase_uid=cl.owner_uid
   WHERE cl.id=r.club_id AND cl.deleted_at IS NULL AND cl.moderation_status='visible' AND NOT EXISTS(SELECT 1 FROM club_reports clr WHERE clr.club_id=cl.id AND clr.reporter_uid=$1) AND cop.deletion_requested_at IS NULL AND ${unblocked('$1', 'cl.owner_uid')}))
 AND NOT EXISTS(SELECT 1 FROM post_reports pr WHERE pr.reporter_uid=$1 AND pr.post_id=r.id)`;
export const postCommentVisible = commentVisible.replaceAll(
  'comment_reports',
  'post_comment_reports',
);
export const reportQuotaSQL = `SELECT (
 (SELECT count(*) FROM club_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours')+
 (SELECT count(*) FROM review_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours')+
 (SELECT count(*) FROM comment_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours')+
 (SELECT count(*) FROM post_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours')+
 (SELECT count(*) FROM post_comment_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours'))::int AS count`;

export const postParentVisible = postCommentVisible
  .replaceAll(/\bc\./g, 'pc.')
  .replaceAll(/\bcp\./g, 'pp.');
