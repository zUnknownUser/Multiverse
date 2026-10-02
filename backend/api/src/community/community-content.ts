import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { unblocked } from '../social/social-policy.js';

export interface PostInput {
  universeID: string;
  itemID: string | null;
  title: string;
  text: string;
  spoiler: boolean;
  segment?: number;
  imageIDs?: string[];
  kind?: 'discussion' | 'theory' | 'duel' | 'room';
  clubID?: string | null;
  scheduleID?: string | null;
  optionA?: string | null;
  optionB?: string | null;
  closesAt?: string | null;
}
export const imageField = `coalesce((SELECT json_agg(json_build_object('id',i.id,'width',i.width,'height',i.height) ORDER BY pi.position)
  FROM post_images pi JOIN community_images i ON i.id=pi.image_id WHERE pi.post_id=r.id),'[]'::json) AS images`;
export const voteField = `json_build_object('counts',json_build_array(
  (SELECT count(*)::int FROM community_votes v JOIN profiles vp ON vp.firebase_uid=v.firebase_uid WHERE v.post_id=r.id AND v.choice=0 AND vp.deletion_requested_at IS NULL AND ${unblocked('$1', 'v.firebase_uid')}),
  (SELECT count(*)::int FROM community_votes v JOIN profiles vp ON vp.firebase_uid=v.firebase_uid WHERE v.post_id=r.id AND v.choice=1 AND vp.deletion_requested_at IS NULL AND ${unblocked('$1', 'v.firebase_uid')})),
  'mine',(SELECT choice FROM community_votes WHERE post_id=r.id AND firebase_uid=$1)) AS votes`;
export async function validateContext(
  client: PoolClient,
  uid: string,
  input: PostInput,
) {
  const catalog = await client.query(
    `SELECT 1 FROM catalog_universes u WHERE u.id=$1 AND u.status='active'
    AND ($2::text IS NULL OR EXISTS(SELECT 1 FROM catalog_items i WHERE i.id=$2 AND i.universe_id=u.id AND i.status='published'))`,
    [input.universeID, input.itemID],
  );
  if (!catalog.rowCount)
    throw new BadRequestException({ code: 'INVALID_POST_CATALOG' });
  if (input.clubID) {
    const club = await client.query(
      `SELECT 1 FROM community_clubs cl JOIN club_members cm ON cm.club_id=cl.id AND cm.firebase_uid=$1
      JOIN profiles cp ON cp.firebase_uid=cl.owner_uid WHERE cl.id=$2 AND cl.universe_id=$3 AND cl.deleted_at IS NULL AND cl.moderation_status='visible' AND NOT EXISTS(SELECT 1 FROM club_reports clr WHERE clr.club_id=cl.id AND clr.reporter_uid=$1) AND cp.deletion_requested_at IS NULL
      AND ${unblocked('$1', 'cl.owner_uid')} FOR SHARE OF cl`,
      [uid, input.clubID, input.universeID],
    );
    if (!club.rowCount)
      throw new ForbiddenException({ code: 'CLUB_MEMBERSHIP_REQUIRED' });
  }
  if (
    input.scheduleID &&
    (!input.clubID ||
      !(
        await client.query(
          'SELECT 1 FROM club_schedule WHERE id=$1 AND club_id=$2 AND item_id=$3',
          [input.scheduleID, input.clubID, input.itemID],
        )
      ).rowCount)
  )
    throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
  const kind = input.kind ?? 'discussion';
  if (kind === 'duel') {
    const end = Date.parse(input.closesAt ?? '');
    if (
      !input.optionA ||
      !input.optionB ||
      input.optionA === input.optionB ||
      !Number.isFinite(end) ||
      end <= Date.now() ||
      end > Date.now() + 30 * 86400000
    )
      throw new BadRequestException({ code: 'INVALID_DUEL' });
  } else if (input.optionA || input.optionB || input.closesAt)
    throw new BadRequestException({ code: 'INVALID_DUEL' });
  if (
    kind === 'room' &&
    (input.segment ?? 0) > 0 &&
    !(
      await client.query(
        'SELECT 1 FROM room_visits WHERE item_id=$1 AND firebase_uid=$2 AND progress >= $3',
        [input.itemID, uid, (input.segment ?? 0) * 50],
      )
    ).rowCount
  )
    throw new ForbiddenException({ code: 'ROOM_PROGRESS_REQUIRED' });
  if (kind !== 'room' && input.segment)
    throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
  if (kind === 'room' && (!input.itemID || input.clubID))
    throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
}
export async function attachImages(
  client: PoolClient,
  uid: string,
  post: string,
  ids: string[],
) {
  if (ids.length > 4 || new Set(ids).size !== ids.length)
    throw new BadRequestException({ code: 'INVALID_IMAGE' });
  const images = await client.query(
    'SELECT id FROM community_images WHERE id=ANY($1::uuid[]) AND firebase_uid=$2 AND draft_post_id=$3 FOR SHARE',
    [ids, uid, post],
  );
  if (images.rowCount !== ids.length)
    throw new BadRequestException({ code: 'INVALID_IMAGE' });
  await client.query('DELETE FROM post_images WHERE post_id=$1', [post]);
  for (const [index, id] of ids.entries())
    await client.query(
      'INSERT INTO post_images(image_id,post_id,position) VALUES($1,$2,$3)',
      [id, post, index],
    );
}
export async function requireEditable(
  client: PoolClient,
  uid: string,
  id: string,
) {
  const row = (
    await client.query(
      "SELECT * FROM community_posts WHERE id=$1 AND firebase_uid=$2 AND deleted_at IS NULL AND moderation_status='visible' FOR UPDATE",
      [id, uid],
    )
  ).rows[0];
  if (!row) throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
  return row;
}
export function stale() {
  return new ConflictException({ code: 'POST_STALE' });
}
