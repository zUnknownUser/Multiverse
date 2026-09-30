import {
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { QueryResultRow } from 'pg';
import { DatabaseService } from '../database/database.service.js';
import { AccountLifecycleService } from './account-lifecycle.service.js';
import type { OnboardingDTO, ProfileDTO } from './account.dto.js';

type ProfileRow = QueryResultRow & {
  firebase_uid: string;
  username: string;
  display_name: string;
  avatar_color: string;
  bio: string;
  created_at: Date;
  updated_at: Date;
  deletion_requested_at: Date | null;
};
type OnboardingRow = QueryResultRow & {
  universe_ids: string[];
  seen_item_ids: string[];
  followed_user_ids: string[];
  step: number;
  completed: boolean;
  version: number;
};
const emptyOnboarding = () => ({
  universeIDs: [],
  seenItemIDs: [],
  followedUserIDs: [],
  step: 1,
  completed: false,
  version: 0,
});
function profile(row: ProfileRow) {
  return {
    userID: row.firebase_uid,
    username: row.username,
    displayName: row.display_name,
    avatarColor: row.avatar_color,
    bio: row.bio,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
function onboarding(row?: OnboardingRow) {
  return row
    ? {
        universeIDs: row.universe_ids,
        seenItemIDs: row.seen_item_ids,
        followedUserIDs: row.followed_user_ids,
        step: row.step,
        completed: row.completed,
        version: row.version,
      }
    : emptyOnboarding();
}
const reserved = new Set([
  'admin',
  'multiverse',
  'support',
  'suporte',
  'moderator',
  'moderacao',
]);

@Injectable()
export class AccountsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
  ) {}
  async me(uid: string) {
    await this.lifecycle.assertActive(uid);
    const result = await this.db.query<ProfileRow>(
      'SELECT * FROM profiles WHERE firebase_uid=$1',
      [uid],
    );
    const row = result.rows[0];
    if (row?.deletion_requested_at)
      throw new ForbiddenException({ code: 'ACCOUNT_DELETING' });
    const progress = await this.db.query<OnboardingRow>(
      // Deletion can remain pending while Firebase is unavailable. Return a
      // recoverable draft immediately, without mutating its optimistic version.
      `SELECT o.universe_ids,o.seen_item_ids,o.step,o.completed,o.version,
        ARRAY(
          SELECT p.firebase_uid
          FROM unnest(o.followed_user_ids) WITH ORDINALITY AS selected(uid,ordinal)
          JOIN profiles p ON p.firebase_uid=selected.uid
          JOIN onboarding eligible ON eligible.firebase_uid=p.firebase_uid
          WHERE p.firebase_uid<>o.firebase_uid AND p.deletion_requested_at IS NULL AND eligible.completed=true
          ORDER BY selected.ordinal
        ) AS followed_user_ids
        FROM onboarding o WHERE o.firebase_uid=$1`,
      [uid],
    );
    return {
      profile: row ? profile(row) : null,
      onboarding: onboarding(progress.rows[0]),
    };
  }
  async availability(uid: string, username: string) {
    if (reserved.has(username)) return { available: false };
    const result = await this.db.query(
      'SELECT 1 FROM profiles WHERE username=$1 AND firebase_uid<>$2',
      [username, uid],
    );
    return { available: result.rowCount === 0 };
  }
  async saveProfile(uid: string, input: ProfileDTO) {
    if (reserved.has(input.username))
      throw new ConflictException({ code: 'USERNAME_TAKEN' });
    try {
      return await this.lifecycle.withActiveAccount(uid, async (client) => {
        const result = await client.query<ProfileRow>(
          `INSERT INTO profiles(firebase_uid,username,display_name,avatar_color,bio)
        VALUES($1,$2,$3,$4,$5) ON CONFLICT(firebase_uid) DO UPDATE SET username=EXCLUDED.username,
        display_name=EXCLUDED.display_name,avatar_color=EXCLUDED.avatar_color,bio=EXCLUDED.bio,updated_at=now()
        WHERE profiles.deletion_requested_at IS NULL RETURNING *`,
          [
            uid,
            input.username,
            input.displayName,
            input.avatarColor,
            input.bio,
          ],
        );
        if (!result.rows[0])
          throw new ForbiddenException({ code: 'ACCOUNT_DELETING' });
        return profile(result.rows[0]);
      });
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === '23505'
      )
        throw new ConflictException({ code: 'USERNAME_TAKEN' });
      throw error;
    }
  }
  async suggestions(uid: string) {
    const result = await this.db.query<ProfileRow>(
      `SELECT p.* FROM profiles p JOIN onboarding o USING(firebase_uid)
      WHERE p.firebase_uid<>$1 AND p.deletion_requested_at IS NULL AND o.completed=true
      ORDER BY p.created_at, p.firebase_uid LIMIT 20`,
      [uid],
    );
    return {
      users: result.rows.map(profile),
      minimumFollows: Math.min(3, result.rows.length),
    };
  }
  async saveOnboarding(uid: string, input: OnboardingDTO) {
    return this.db.transaction(async (client) => {
      const owner = await client.query<ProfileRow>(
        // Protect against profile deletion while allowing other onboarding reads.
        // Progress writes are serialized by the onboarding row lock below.
        'SELECT * FROM profiles WHERE firebase_uid=$1 FOR SHARE',
        [uid],
      );
      if (!owner.rows[0])
        throw new NotFoundException({ code: 'PROFILE_REQUIRED' });
      if (owner.rows[0].deletion_requested_at)
        throw new ForbiddenException({ code: 'ACCOUNT_DELETING' });
      await client.query(
        'INSERT INTO onboarding(firebase_uid) VALUES($1) ON CONFLICT DO NOTHING',
        [uid],
      );
      const current = (
        await client.query<OnboardingRow>(
          'SELECT * FROM onboarding WHERE firebase_uid=$1 FOR UPDATE',
          [uid],
        )
      ).rows[0];
      if (current.version !== input.version)
        throw new ConflictException({ code: 'STALE_ONBOARDING' });
      if (current.completed && !input.completed)
        throw new ConflictException({ code: 'ONBOARDING_COMPLETED' });
      if ((input.step > 1 || input.completed) && !input.universeIDs.length)
        throw new ConflictException({ code: 'UNIVERSE_REQUIRED' });
      if (input.followedUserIDs.includes(uid))
        throw new ConflictException({ code: 'INVALID_FOLLOWS' });
      const eligible = await client.query<{ firebase_uid: string }>(
        `SELECT p.firebase_uid FROM profiles p JOIN onboarding o USING(firebase_uid)
        WHERE p.firebase_uid=ANY($1::text[]) AND p.firebase_uid<>$2 AND p.deletion_requested_at IS NULL AND o.completed=true FOR SHARE OF p`,
        [input.followedUserIDs, uid],
      );
      if (eligible.rowCount !== input.followedUserIDs.length)
        throw new ConflictException({ code: 'INVALID_FOLLOWS' });
      const total = (
        await client.query<{ count: string }>(
          `SELECT count(*) FROM profiles p JOIN onboarding o USING(firebase_uid)
        WHERE p.firebase_uid<>$1 AND p.deletion_requested_at IS NULL AND o.completed=true`,
          [uid],
        )
      ).rows[0];
      const minimum = Math.min(3, Number(total.count));
      if (input.completed && input.followedUserIDs.length < minimum)
        throw new ConflictException({
          code: 'FOLLOWS_REQUIRED',
          minimumFollows: minimum,
        });
      const saved = await client.query<OnboardingRow>(
        `UPDATE onboarding SET universe_ids=$2,seen_item_ids=$3,followed_user_ids=$4,
        step=$5,completed=$6,version=version+1,updated_at=now() WHERE firebase_uid=$1 RETURNING *`,
        [
          uid,
          input.universeIDs,
          input.seenItemIDs,
          input.followedUserIDs,
          input.step,
          input.completed,
        ],
      );
      await client.query('DELETE FROM follows WHERE follower_uid=$1', [uid]);
      await client.query(
        'INSERT INTO follows(follower_uid,followed_uid) SELECT $1,unnest($2::text[])',
        [uid, input.followedUserIDs],
      );
      return onboarding(saved.rows[0]);
    });
  }
}
