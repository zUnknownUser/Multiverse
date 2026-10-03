import {
  ConflictException,
  HttpException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService } from '../social/social.service.js';
export interface OrderMutation {
  mutationID: string;
  version: number;
  orderID: string;
  action: 'following' | 'voted';
  enabled: boolean;
}
// Never silently remove an unavailable step: hide the entire journey until reviewed.
const published = `r.status='published' AND u.status='active' AND u.id IN ('marvel','dc')
 AND EXISTS(SELECT 1 FROM reading_order_steps s WHERE s.order_id=r.id)
 AND EXISTS(SELECT 1 FROM reading_order_translations rt WHERE rt.order_id=r.id AND rt.locale='pt-BR')
 AND EXISTS(SELECT 1 FROM reading_order_translations rt WHERE rt.order_id=r.id AND rt.locale='en')
 AND NOT EXISTS(SELECT 1 FROM reading_order_steps s JOIN catalog_items i ON i.id=s.item_id
 WHERE s.order_id=r.id AND (i.status<>'published' OR i.universe_id<>r.universe_id OR i.type<>'HQ'
 OR NOT EXISTS(SELECT 1 FROM catalog_item_translations it WHERE it.item_id=i.id AND it.locale='pt-BR'))) `;
@Injectable()
export class ReadingOrdersService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}
  private async snapshot(c: PoolClient, uid: string, locale: 'pt-BR' | 'en') {
    const version =
      (
        await c.query(
          'SELECT version FROM reading_order_state WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0]?.version ?? 0;
    const orders = await c.query(
      `SELECT r.id,r.universe_id AS uni,t.title,t.description,'multiverse' AS by,
   ARRAY(SELECT s.item_id FROM reading_order_steps s WHERE s.order_id=r.id ORDER BY s.position) AS steps,
   coalesce(m.following,false) AS following,coalesce(m.voted,false) AS voted,
   (SELECT count(*)::int FROM reading_order_marks cm JOIN profiles p USING(firebase_uid) JOIN onboarding o USING(firebase_uid) WHERE cm.order_id=r.id AND cm.voted AND p.deletion_requested_at IS NULL AND o.completed) AS votes,
   (SELECT count(*)::int FROM reading_order_marks cm JOIN profiles p USING(firebase_uid) JOIN onboarding o USING(firebase_uid) WHERE cm.order_id=r.id AND cm.following AND p.deletion_requested_at IS NULL AND o.completed) AS followers
   FROM reading_orders r JOIN catalog_universes u ON u.id=r.universe_id JOIN reading_order_translations t ON t.order_id=r.id AND t.locale=$2
   LEFT JOIN reading_order_marks m ON m.order_id=r.id AND m.firebase_uid=$1
   WHERE ${published} ORDER BY r.sort_order,r.id`,
      [uid, locale],
    );
    return { version, locale, orders: orders.rows };
  }
  read(uid: string, locale: 'pt-BR' | 'en') {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      return this.snapshot(c, uid, locale);
    });
  }
  mutate(uid: string, locale: 'pt-BR' | 'en', input: OrderMutation) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      const prior = (
        await c.query(
          'SELECT applied_version,request=$3::jsonb AS same FROM reading_order_mutations WHERE firebase_uid=$1 AND id=$2',
          [uid, input.mutationID, JSON.stringify(input)],
        )
      ).rows[0];
      if (prior) {
        if (!prior.same)
          throw new ConflictException({ code: 'ORDER_CONFLICT' });
        return {
          mutationID: input.mutationID,
          appliedVersion: prior.applied_version,
          state: await this.snapshot(c, uid, locale),
        };
      }
      await c.query(
        'INSERT INTO reading_order_state(firebase_uid) VALUES($1) ON CONFLICT DO NOTHING',
        [uid],
      );
      const version = (
        await c.query(
          'SELECT version FROM reading_order_state WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0].version;
      if (version !== input.version)
        throw new ConflictException({ code: 'ORDER_STALE' });
      const available = await c.query(
        `SELECT r.id FROM reading_orders r JOIN catalog_universes u ON u.id=r.universe_id WHERE r.id=$1 AND ${published} FOR SHARE OF r,u`,
        [input.orderID],
      );
      if (!available.rowCount)
        throw new NotFoundException({ code: 'ORDER_UNAVAILABLE' });
      const count = (
        await c.query(
          "SELECT count(*)::int AS n FROM reading_order_mutations WHERE firebase_uid=$1 AND created_at>now()-interval '1 hour'",
          [uid],
        )
      ).rows[0].n;
      if (count >= 120) throw new HttpException({ code: 'ORDER_LIMIT' }, 429);
      const column = input.action === 'following' ? 'following' : 'voted';
      await c.query(
        `INSERT INTO reading_order_marks(firebase_uid,order_id,${column}) VALUES($1,$2,$3) ON CONFLICT(firebase_uid,order_id) DO UPDATE SET ${column}=EXCLUDED.${column}`,
        [uid, input.orderID, input.enabled],
      );
      await c.query(
        'UPDATE reading_order_state SET version=version+1 WHERE firebase_uid=$1',
        [uid],
      );
      await c.query(
        'INSERT INTO reading_order_mutations(firebase_uid,id,request,applied_version) VALUES($1,$2,$3,$4)',
        [uid, input.mutationID, JSON.stringify(input), version + 1],
      );
      return {
        mutationID: input.mutationID,
        appliedVersion: version + 1,
        state: await this.snapshot(c, uid, locale),
      };
    });
  }
}
