import { createHash } from 'node:crypto';
import { BadRequestException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import type { ActivityQuery } from './activity-query.js';

/** Reads only the selected history page; account-wide facts are independent of that page. */
export async function activityPage(
  client: PoolClient,
  uid: string,
  locale: string,
  query?: ActivityQuery,
  savedID?: string,
) {
  let selectedIDs: string[] | null = null;
  let nextCursor: string | null = null;
  let summary;
  if (query) {
    // Scope the continuation to the account, locale and filters; SQL always uses the authenticated UID.
    const scope = createHash('sha256')
      .update(
        JSON.stringify([
          uid,
          locale,
          query.search,
          query.selection,
          query.year,
          query.timeZone,
          query.itemId,
          query.universeId,
        ]),
      )
      .digest('hex');
    let anchor: string[] | null = null;
    if (query.after) {
      try {
        const value = JSON.parse(
          Buffer.from(query.after, 'base64url').toString(),
        );
        if (
          value.scope !== scope ||
          !Array.isArray(value.anchor) ||
          value.anchor.length !== 3 ||
          !value.anchor.every((v: unknown) => typeof v === 'string') ||
          !value.anchor
            .slice(0, 2)
            .every(
              (v: string) =>
                /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(v) &&
                !Number.isNaN(Date.parse(v)) &&
                new Date(v).toISOString() === v.slice(0, 23) + 'Z',
            ) ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
            value.anchor[2],
          )
        )
          throw new Error();
        anchor = value.anchor;
      } catch {
        throw new BadRequestException({ code: 'INVALID_ACTIVITY_QUERY' });
      }
    }
    const page = await client.query(
      `SELECT d.id,
        to_char(d.logged_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS logged,
        to_char(d.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS created
        FROM diary_entries d JOIN catalog_items i ON i.id=d.item_id
        JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
        LEFT JOIN catalog_item_translations t ON t.item_id=i.id AND t.locale=$2
        WHERE d.firebase_uid=$1 AND i.universe_id IN ('marvel','dc')
        AND ($3='all' OR ($3='liked' AND d.liked) OR ($3='rated' AND d.rating>0) OR ($3='rewatched' AND d.rewatch) OR ($3='reviewed' AND EXISTS(SELECT 1 FROM reviews r WHERE r.firebase_uid=d.firebase_uid AND r.entry_id=d.id)))
        AND ($11::text IS NULL OR d.item_id=$11) AND ($12::text IS NULL OR i.universe_id=$12)
        AND ($4::int IS NULL OR extract(year FROM d.logged_at AT TIME ZONE $5)=$4)
        AND NOT EXISTS(SELECT 1 FROM unnest($6::text[]) word WHERE strpos(translate(lower(coalesce(t.title,p.title)),
          'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),word)=0)
        AND ($7::timestamptz IS NULL OR d.logged_at<$7 OR (d.logged_at=$7 AND d.created_at<$8) OR
          (d.logged_at=$7 AND d.created_at=$8 AND d.id>$9::uuid))
        ORDER BY d.logged_at DESC,d.created_at DESC,d.id LIMIT $10`,
      [
        uid,
        locale,
        query.selection,
        query.year ?? null,
        query.timeZone,
        query.search
          .normalize('NFD')
          .replace(/\p{M}/gu, '')
          .toLowerCase()
          .split(/\s+/)
          .filter(Boolean),
        anchor?.[0] ?? null,
        anchor?.[1] ?? null,
        anchor?.[2] ?? null,
        query.limit + 1,
        query.itemId ?? null,
        query.universeId ?? null,
      ],
    );
    selectedIDs = page.rows.slice(0, query.limit).map((row) => row.id);
    if (page.rows.length > query.limit) {
      const last = page.rows[query.limit - 1];
      nextCursor = Buffer.from(
        JSON.stringify({
          scope,
          anchor: [last.logged, last.created, last.id],
        }),
      ).toString('base64url');
    }
    // Mutation acknowledgements always include the exact edited UUID, even outside the first page.
    if (savedID && !selectedIDs.includes(savedID)) selectedIDs.push(savedID);
    const latest = await client.query(
      `SELECT id,"itemId","loggedAt",rating,liked,rewatch FROM (SELECT DISTINCT ON (d.item_id) d.created_at,d.id,d.item_id AS "itemId",d.logged_at AS "loggedAt",d.rating,d.liked,d.rewatch
        FROM diary_entries d JOIN catalog_items i ON i.id=d.item_id WHERE d.firebase_uid=$1 AND i.universe_id IN ('marvel','dc')
        ORDER BY d.item_id,d.logged_at DESC,d.created_at DESC,d.id) latest ORDER BY "loggedAt" DESC,created_at DESC,id`,
      [uid],
    );
    const totals = await client.query(
      `SELECT count(*)::int AS total,
        count(r.id)::int AS "reviewCount",coalesce(avg(d.rating) FILTER(WHERE r.id IS NOT NULL),0)::float8 AS "averageRating",
        coalesce(array_agg(DISTINCT extract(year FROM d.logged_at AT TIME ZONE $2)::int),ARRAY[]::int[]) AS years
        FROM diary_entries d JOIN catalog_items i ON i.id=d.item_id
        LEFT JOIN reviews r ON r.firebase_uid=d.firebase_uid AND r.entry_id=d.id
        WHERE d.firebase_uid=$1 AND i.universe_id IN ('marvel','dc')`,
      [uid, query.timeZone],
    );
    const buckets = await client.query(
      `SELECT extract(year FROM d.logged_at AT TIME ZONE $2)::int AS year,
        i.type,i.universe_id AS universe,count(*)::int AS count FROM diary_entries d
        JOIN catalog_items i ON i.id=d.item_id WHERE d.firebase_uid=$1 AND i.universe_id IN ('marvel','dc')
        GROUP BY 1,2,3 ORDER BY 1,2,3`,
      [uid, query.timeZone],
    );
    const days = await client.query(
      `SELECT DISTINCT to_char(d.logged_at AT TIME ZONE $2,'YYYY-MM-DD') AS day
        FROM diary_entries d JOIN catalog_items i ON i.id=d.item_id WHERE d.firebase_uid=$1 AND i.universe_id IN ('marvel','dc')
        AND (d.logged_at AT TIME ZONE $2)::date >= (now() AT TIME ZONE $2)::date - 104
        ORDER BY day`,
      [uid, query.timeZone],
    );
    const recent = await client.query(
      `SELECT r.id,r.entry_id AS "entryId",r.firebase_uid AS "user",d.item_id AS item,d.rating,r.text,r.spoiler,
        r.created_at AS "createdAt" FROM reviews r JOIN diary_entries d ON d.firebase_uid=r.firebase_uid AND d.id=r.entry_id
        JOIN catalog_items i ON i.id=d.item_id WHERE r.firebase_uid=$1 AND i.universe_id IN ('marvel','dc')
        ORDER BY r.created_at DESC,r.id LIMIT 4`,
      [uid],
    );
    summary = {
      ...totals.rows[0],
      latestEntries: latest.rows,
      recentReviews: recent.rows,
      buckets: buckets.rows,
      activeDays: days.rows.map((row) => row.day),
    };
  }
  const metadataIDs: string[] = summary
    ? [
        ...summary.latestEntries
          .filter((e: { liked: boolean }) => e.liked)
          .slice(0, 4)
          .map((e: { itemId: string }) => e.itemId),
        ...summary.recentReviews.map((r: { item: string }) => r.item),
      ]
    : [];
  return { selectedIDs, nextCursor, summary, metadataIDs };
}
