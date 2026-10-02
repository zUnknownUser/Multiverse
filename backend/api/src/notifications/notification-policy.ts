import {
  unblocked,
  reviewRelations,
  reviewVisible,
  commentVisible,
} from '../social/social-policy.js';
import {
  postRelations,
  postVisible,
  postCommentVisible,
} from '../community/community-policy.js';
// $1 is ALWAYS the recipient/viewer, n is the notification. Revalidate at read AND delivery time.
function discussion(domain: 'review' | 'post') {
  const post = domain === 'post',
    parents = post ? postRelations : reviewRelations,
    visible = post ? postVisible : reviewVisible;
  const comments = post ? 'post_comments' : 'review_comments',
    reactions = post ? 'post_reactions' : 'social_reactions',
    key = post ? 'post_id' : 'review_id';
  return `(n.target_type='${domain}' AND EXISTS(SELECT 1 FROM ${parents} WHERE r.id::text=n.target_id AND ${visible}
 AND (n.comment_id IS NULL OR EXISTS(SELECT 1 FROM ${comments} c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid WHERE c.id=n.comment_id AND c.${key}=r.id AND ${post ? postCommentVisible : commentVisible}))
 AND (n.kind<>'mention' OR EXISTS(SELECT 1 FROM community_mentions m WHERE m.post_id::text=n.target_id AND m.comment_id IS NOT DISTINCT FROM n.comment_id AND m.recipient_uid=$1))
 AND (n.kind<>'reaction' OR EXISTS(SELECT 1 FROM ${reactions} sr WHERE sr.target_id=coalesce(n.comment_id,r.id) AND sr.firebase_uid=n.actor_uid AND (sr.liked OR sr.reaction IS NOT NULL)))))`;
}
export const notificationVisible = `n.recipient_uid=$1 AND ap.deletion_requested_at IS NULL AND ao.completed=true
 AND ${unblocked('$1', 'n.actor_uid')} AND (
 (n.kind='follow' AND n.target_type='person' AND EXISTS(SELECT 1 FROM visible_follows f WHERE f.follower_uid=n.actor_uid AND f.followed_uid=$1))
 OR ${discussion('review')} OR ${discussion('post')})`;
export const notificationRelations = `notifications n JOIN profiles ap ON ap.firebase_uid=n.actor_uid JOIN onboarding ao ON ao.firebase_uid=ap.firebase_uid`;
