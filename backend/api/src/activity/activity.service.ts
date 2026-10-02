import {
  catalogSeriesJoin,
  catalogSeriesField,
} from '../catalog/catalog-series.js';
import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  HttpException,
  NotFoundException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import type { SaveLogDTO } from './activity.dto.js';
import {
  catalogDescription,
  descriptionSourceJoin,
} from '../catalog/catalog-description.js';

@Injectable()
export class ActivityService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
  ) {}

  private async assertProfile(client: PoolClient, uid: string) {
    const profile = await client.query(
      'SELECT 1 FROM profiles WHERE firebase_uid=$1 AND deletion_requested_at IS NULL FOR SHARE',
      [uid],
    );
    if (!profile.rowCount)
      throw new NotFoundException({ code: 'PROFILE_REQUIRED' });
  }

  async read(uid: string, locale: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.assertProfile(client, uid);
      return this.snapshot(client, uid, locale);
    });
  }

  async save(uid: string, id: string, input: SaveLogDTO, locale: string) {
    if (new Date(input.loggedAt).getTime() > Date.now() + 300_000)
      throw new BadRequestException({ code: 'INVALID_LOG_DATE' });
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.assertProfile(client, uid);
      const item = await client.query(
        `SELECT i.id FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id
        WHERE i.id=$1 AND i.status='published' AND u.status='active' FOR SHARE OF i,u`,
        [input.itemId],
      );
      if (!item.rowCount)
        throw new ConflictException({ code: 'ITEM_UNAVAILABLE' });
      if (input.text || input.rating > 0) {
        const budget = await client.query(
          `SELECT p.public_diary,
           EXISTS(SELECT 1 FROM reviews WHERE firebase_uid=$1 AND entry_id=$2) AS existing,
           (SELECT count(*)::int FROM reviews WHERE firebase_uid=$1 AND created_at>now()-interval '1 hour') AS recent
           FROM profiles p WHERE p.firebase_uid=$1`,
          [uid, id],
        );
        const { public_diary, existing, recent } = budget.rows[0];
        if (public_diary && !existing && recent >= 20)
          throw new HttpException({ code: 'PUBLICATION_LIMIT' }, 429);
      }
      // The client keeps this UUID across retries, including lost HTTP responses.
      await client.query(
        `INSERT INTO diary_entries(firebase_uid,id,item_id,logged_at,rating,liked,rewatch)
        VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(firebase_uid,id) DO UPDATE SET
        item_id=EXCLUDED.item_id,logged_at=EXCLUDED.logged_at,rating=EXCLUDED.rating,
        liked=EXCLUDED.liked,rewatch=EXCLUDED.rewatch,updated_at=CASE WHEN
        (diary_entries.item_id,diary_entries.logged_at,diary_entries.rating,diary_entries.liked,diary_entries.rewatch)
        IS DISTINCT FROM (EXCLUDED.item_id,EXCLUDED.logged_at,EXCLUDED.rating,EXCLUDED.liked,EXCLUDED.rewatch)
        THEN now() ELSE diary_entries.updated_at END`,
        [
          uid,
          id,
          input.itemId,
          input.loggedAt,
          input.rating,
          input.liked,
          input.rewatch,
        ],
      );
      if (input.text || input.rating > 0) {
        await client.query(
          `INSERT INTO reviews(firebase_uid,entry_id,text,spoiler) VALUES($1,$2,$3,$4)
          ON CONFLICT(firebase_uid,entry_id) DO UPDATE SET text=EXCLUDED.text,spoiler=EXCLUDED.spoiler`,
          [uid, id, input.text, input.spoiler],
        );
      } else {
        await client.query(
          'DELETE FROM reviews WHERE firebase_uid=$1 AND entry_id=$2',
          [uid, id],
        );
      }
      return this.snapshot(client, uid, locale);
    });
  }

  private async snapshot(client: PoolClient, uid: string, locale: string) {
    const entries = await client.query(
      `SELECT id,item_id AS "itemId",logged_at AS "loggedAt",rating,liked,rewatch
      FROM diary_entries WHERE firebase_uid=$1 ORDER BY logged_at DESC,created_at DESC,id`,
      [uid],
    );
    const reviews = await client.query(
      `SELECT r.id,r.firebase_uid AS "user",d.item_id AS item,d.rating,r.text,r.spoiler,
      r.created_at AS "createdAt" FROM reviews r JOIN diary_entries d ON d.firebase_uid=r.firebase_uid AND d.id=r.entry_id
      WHERE r.firebase_uid=$1 ORDER BY r.created_at DESC,r.id`,
      [uid],
    );
    // Include archived references so a catalog retirement never erases a diary row.
    const items = await client.query(
      `SELECT i.id,i.universe_id AS uni,i.type,coalesce(t.title,p.title) AS title,
      coalesce(t.year,p.year) AS year,s.average AS avg,s.log_count AS "logCount",s.review_count AS "reviewCount",
      s.rating_histogram AS "ratingHistogram",
      coalesce(t.canon,p.canon) AS canon,${catalogDescription('$2')} AS "desc",${catalogSeriesField}
      FROM catalog_items i JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
      LEFT JOIN catalog_item_translations t ON t.item_id=i.id AND t.locale=$2
      ${descriptionSourceJoin} ${catalogSeriesJoin('$2')}
      JOIN catalog_item_statistics s ON s.item_id=i.id
      WHERE i.id IN (SELECT item_id FROM diary_entries WHERE firebase_uid=$1) ORDER BY i.sort_order,i.id`,
      [uid, locale],
    );
    const universes = await client.query(
      `SELECT u.id,coalesce(t.name,p.name) AS name,u.color AS c,u.dark_color AS c2,
      u.ink_color AS ink,u.track,coalesce(t.canon,p.canon) AS canon,coalesce(t.tagline,p.tagline) AS tagline,
      0 AS base,0 AS total,0 AS members,0 AS live FROM catalog_universes u
      JOIN catalog_universe_translations p ON p.universe_id=u.id AND p.locale='pt-BR'
      LEFT JOIN catalog_universe_translations t ON t.universe_id=u.id AND t.locale=$2
      WHERE u.id IN (SELECT i.universe_id FROM catalog_items i JOIN diary_entries d ON d.item_id=i.id WHERE d.firebase_uid=$1)
      ORDER BY u.sort_order,u.id`,
      [uid, locale],
    );
    const followers = await client.query(
      `SELECT count(*)::int AS count FROM visible_follows f JOIN profiles p ON p.firebase_uid=f.follower_uid
      WHERE f.followed_uid=$1 AND p.deletion_requested_at IS NULL`,
      [uid],
    );
    return {
      entries: entries.rows,
      reviews: reviews.rows,
      items: items.rows,
      universes: universes.rows,
      followerCount: followers.rows[0].count,
    };
  }
}
