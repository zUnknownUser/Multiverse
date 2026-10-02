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
import type { LibraryMutationDTO } from './library.dto.js';
@Injectable()
export class LibraryService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}
  private async state(client: PoolClient, uid: string) {
    const version =
      (
        await client.query(
          'SELECT version FROM library_state WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0]?.version ?? 0;
    const marks = (
      await client.query(
        'SELECT item_id,wanted,favorite FROM library_marks WHERE firebase_uid=$1 ORDER BY item_id',
        [uid],
      )
    ).rows;
    const lists = await client.query(
      `SELECT l.id,l.title,l.description,l.created_at AS "createdAt",l.updated_at AS "updatedAt",
   ARRAY(SELECT i.item_id FROM personal_list_items i WHERE i.list_id=l.id ORDER BY i.added_at,i.item_id) AS "itemIDs"
   FROM personal_lists l WHERE l.firebase_uid=$1 ORDER BY l.created_at DESC,l.id DESC`,
      [uid],
    );
    return {
      version,
      wantedIDs: marks.filter((r) => r.wanted).map((r) => r.item_id),
      favoriteIDs: marks.filter((r) => r.favorite).map((r) => r.item_id),
      lists: lists.rows,
    };
  }
  async read(uid: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      return this.state(client, uid);
    });
  }
  private async item(client: PoolClient, id: string) {
    if (
      !(
        await client.query(
          "SELECT 1 FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id WHERE i.id=$1 AND i.status='published' AND u.status='active'",
          [id],
        )
      ).rowCount
    )
      throw new NotFoundException({ code: 'ITEM_UNAVAILABLE' });
  }
  async mutate(uid: string, input: LibraryMutationDTO) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const request = JSON.stringify(input);
      const prior = (
        await client.query(
          'SELECT applied_version,request=$3::jsonb AS same FROM library_mutations WHERE firebase_uid=$1 AND id=$2',
          [uid, input.mutationID, request],
        )
      ).rows[0];
      if (prior) {
        if (!prior.same)
          throw new ConflictException({ code: 'LIBRARY_MUTATION_CONFLICT' });
        return {
          mutationID: input.mutationID,
          appliedVersion: prior.applied_version,
          state: await this.state(client, uid),
        };
      }
      await client.query(
        'INSERT INTO library_state(firebase_uid) VALUES($1) ON CONFLICT DO NOTHING',
        [uid],
      );
      const current = (
        await client.query(
          'SELECT version FROM library_state WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0].version;
      if (current !== input.version)
        throw new ConflictException({ code: 'LIBRARY_STALE' });
      const quota = await client.query(
        `UPDATE library_state SET window_start=date_trunc('minute',now()),requests=CASE WHEN window_start<date_trunc('minute',now()) THEN 1 ELSE requests+1 END
    WHERE firebase_uid=$1 AND (window_start<date_trunc('minute',now()) OR requests<120) RETURNING version`,
        [uid],
      );
      if (!quota.rowCount)
        throw new HttpException({ code: 'LIBRARY_RATE_LIMIT' }, 429);
      if (input.action === 'wanted' || input.action === 'favorite') {
        const column = input.action; // fixed allowlist above, never interpolate arbitrary keys
        const old = (
          await client.query(
            'SELECT wanted,favorite FROM library_marks WHERE firebase_uid=$1 AND item_id=$2',
            [uid, input.itemID],
          )
        ).rows[0];
        if (input.enabled) {
          await this.item(client, input.itemID!);
          if (
            !old &&
            (
              await client.query(
                'SELECT count(*)::int AS n FROM library_marks WHERE firebase_uid=$1',
                [uid],
              )
            ).rows[0].n >= 1000
          )
            throw new ConflictException({ code: 'LIBRARY_ITEMS_LIMIT' });
          await client.query(
            `INSERT INTO library_marks(firebase_uid,item_id,${column}) VALUES($1,$2,true) ON CONFLICT(firebase_uid,item_id) DO UPDATE SET ${column}=true`,
            [uid, input.itemID],
          );
        } else if (old) {
          const other = column === 'wanted' ? 'favorite' : 'wanted';
          if (old[other])
            await client.query(
              `UPDATE library_marks SET ${column}=false WHERE firebase_uid=$1 AND item_id=$2`,
              [uid, input.itemID],
            );
          else
            await client.query(
              'DELETE FROM library_marks WHERE firebase_uid=$1 AND item_id=$2',
              [uid, input.itemID],
            );
        }
      } else if (input.action === 'create_list') {
        if (
          (
            await client.query(
              'SELECT count(*)::int AS n FROM personal_lists WHERE firebase_uid=$1',
              [uid],
            )
          ).rows[0].n >= 50
        )
          throw new ConflictException({ code: 'LIBRARY_LISTS_LIMIT' });
        try {
          await client.query(
            'INSERT INTO personal_lists(id,firebase_uid,title,description) VALUES($1,$2,$3,$4)',
            [input.listID, uid, input.title, input.description],
          );
        } catch (error) {
          if ((error as { code?: string }).code === '23505')
            throw new ConflictException({ code: 'LIBRARY_LIST_CONFLICT' });
          throw error;
        }
      } else {
        if (
          !(
            await client.query(
              'SELECT 1 FROM personal_lists WHERE id=$1 AND firebase_uid=$2',
              [input.listID, uid],
            )
          ).rowCount
        )
          throw new NotFoundException({ code: 'LIST_UNAVAILABLE' });
        if (input.action === 'delete_list')
          await client.query('DELETE FROM personal_lists WHERE id=$1', [
            input.listID,
          ]);
        else if (input.action === 'update_list')
          await client.query(
            'UPDATE personal_lists SET title=$2,description=$3,updated_at=now() WHERE id=$1',
            [input.listID, input.title, input.description],
          );
        else {
          if (input.action === 'add_item') {
            await this.item(client, input.itemID!);
            const old = await client.query(
              'SELECT 1 FROM personal_list_items WHERE list_id=$1 AND item_id=$2',
              [input.listID, input.itemID],
            );
            if (
              !old.rowCount &&
              (
                await client.query(
                  'SELECT count(*)::int AS n FROM personal_list_items WHERE list_id=$1',
                  [input.listID],
                )
              ).rows[0].n >= 200
            )
              throw new ConflictException({ code: 'LIST_ITEMS_LIMIT' });
            await client.query(
              'INSERT INTO personal_list_items(list_id,item_id) VALUES($1,$2) ON CONFLICT DO NOTHING',
              [input.listID, input.itemID],
            );
          } else
            await client.query(
              'DELETE FROM personal_list_items WHERE list_id=$1 AND item_id=$2',
              [input.listID, input.itemID],
            );
          await client.query(
            'UPDATE personal_lists SET updated_at=now() WHERE id=$1',
            [input.listID],
          );
        }
      }
      const version = (
        await client.query(
          'UPDATE library_state SET version=version+1 WHERE firebase_uid=$1 RETURNING version',
          [uid],
        )
      ).rows[0].version;
      await client.query(
        'INSERT INTO library_mutations(firebase_uid,id,request,applied_version) VALUES($1,$2,$3,$4)',
        [uid, input.mutationID, request, version],
      );
      return {
        mutationID: input.mutationID,
        appliedVersion: version,
        state: await this.state(client, uid),
      };
    });
  }
}
