import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';

import { recordNotification } from '../notifications/notification-events.js';
import { unblocked } from '../social/social-policy.js';

const eligible = `profiles p JOIN onboarding o ON o.firebase_uid=p.firebase_uid AND o.completed=true`;
const fields = `p.firebase_uid AS "userID",p.username,p.display_name AS "displayName",p.avatar_color AS "avatarColor",p.bio,
  (SELECT count(*)::int FROM diary_entries d WHERE d.firebase_uid=p.firebase_uid) AS "logCount",
  (SELECT count(*)::int FROM visible_follows f JOIN profiles a ON a.firebase_uid=f.follower_uid
   WHERE f.followed_uid=p.firebase_uid AND a.deletion_requested_at IS NULL) AS "followerCount",
  (SELECT count(*)::int FROM visible_follows f JOIN profiles a ON a.firebase_uid=f.followed_uid
   JOIN onboarding ao ON ao.firebase_uid=a.firebase_uid AND ao.completed=true
   WHERE f.follower_uid=p.firebase_uid AND a.deletion_requested_at IS NULL) AS "followingCount"`;

@Injectable()
export class PeopleService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
  ) {}

  private async requireMember(client: PoolClient, uid: string) {
    const result = await client.query(
      `SELECT 1 FROM ${eligible}
      WHERE p.firebase_uid=$1 AND p.deletion_requested_at IS NULL FOR SHARE OF p`,
      [uid],
    );
    if (!result.rowCount)
      throw new ConflictException({ code: 'ONBOARDING_REQUIRED' });
  }

  private async state(client: PoolClient, uid: string) {
    const result = await client.query(
      `SELECT o.version,
      ARRAY(SELECT f.followed_uid FROM visible_follows f JOIN profiles p ON p.firebase_uid=f.followed_uid
        JOIN onboarding m ON m.firebase_uid=p.firebase_uid AND m.completed=true
        WHERE f.follower_uid=$1 AND p.deletion_requested_at IS NULL ORDER BY f.followed_uid) AS "followingIDs",
      (SELECT count(*)::int FROM visible_follows f JOIN profiles p ON p.firebase_uid=f.follower_uid
        WHERE f.followed_uid=$1 AND p.deletion_requested_at IS NULL) AS "followerCount"
      FROM onboarding o WHERE o.firebase_uid=$1`,
      [uid],
    );
    return result.rows[0];
  }

  async list(
    uid: string,
    query: {
      search: string;
      after?: string;
      limit: number;
      suggestions: boolean;
    },
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.requireMember(client, uid);
      const search = query.search
        .replace(/^@/, '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase();
      const result = await client.query(
        `SELECT ${fields} FROM ${eligible}
        WHERE p.firebase_uid<>$1 AND p.deletion_requested_at IS NULL AND ${unblocked('$1', 'p.firebase_uid')}
        AND strpos(lower(regexp_replace(normalize(p.display_name || ' ' || p.username,NFD),'[\u0300-\u036f]','','g')),$2)>0
        AND ($3::text IS NULL OR p.username COLLATE "C">$3 COLLATE "C")
        AND (NOT $4::boolean OR NOT EXISTS(SELECT 1 FROM visible_follows f WHERE f.follower_uid=$1 AND f.followed_uid=p.firebase_uid))
        ORDER BY p.username COLLATE "C" LIMIT $5`,
        [uid, search, query.after ?? null, query.suggestions, query.limit + 1],
      );
      const users = result.rows.slice(0, query.limit);
      return {
        users,
        nextCursor:
          result.rows.length > users.length ? users.at(-1)!.username : null,
        state: await this.state(client, uid),
      };
    });
  }

  private async person(client: PoolClient, id: string, viewer: string) {
    const result = await client.query(
      `SELECT ${fields} FROM ${eligible} WHERE p.firebase_uid=$1 AND p.deletion_requested_at IS NULL AND ${unblocked('$2', 'p.firebase_uid')}`,
      [id, viewer],
    );
    if (!result.rowCount)
      throw new NotFoundException({ code: 'PERSON_UNAVAILABLE' });
    return result.rows[0];
  }

  async detail(uid: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.requireMember(client, uid);
      return {
        person: await this.person(client, id, uid),
        state: await this.state(client, uid),
      };
    });
  }

  async follow(uid: string, id: string, following: boolean) {
    if (uid === id) throw new ConflictException({ code: 'CANNOT_FOLLOW_SELF' });
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.requireMember(client, uid);
      // Same owner row as onboarding; reciprocal follows never take exclusive locks on target profiles.
      await client.query(
        'SELECT 1 FROM onboarding WHERE firebase_uid=$1 FOR UPDATE',
        [uid],
      );
      const target = await client.query(
        `SELECT 1 FROM ${eligible}
        WHERE p.firebase_uid=$1 AND p.deletion_requested_at IS NULL AND ${unblocked('$2', 'p.firebase_uid')} FOR SHARE OF p`,
        [id, uid],
      );
      if (!target.rowCount)
        throw new NotFoundException({ code: 'PERSON_UNAVAILABLE' });
      const changed = following
        ? await client.query(
            'INSERT INTO follows(follower_uid,followed_uid) VALUES($1,$2) ON CONFLICT DO NOTHING',
            [uid, id],
          )
        : await client.query(
            'DELETE FROM follows WHERE follower_uid=$1 AND followed_uid=$2',
            [uid, id],
          );
      if (changed.rowCount && following)
        await recordNotification(client, id, uid, 'follow', 'person', uid);
      if (changed.rowCount)
        await client.query(
          'UPDATE onboarding SET version=version+1,updated_at=now() WHERE firebase_uid=$1',
          [uid],
        );
      return {
        person: await this.person(client, id, uid),
        state: await this.state(client, uid),
      };
    });
  }
}
