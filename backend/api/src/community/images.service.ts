import { DatabaseService } from '../database/database.service.js';
import {
  BadRequestException,
  ConflictException,
  HttpException,
  Inject,
  Injectable,
  NotFoundException,
  type OnModuleInit,
  type OnModuleDestroy,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService } from '../social/social.service.js';
import { postRelations, postVisible } from './community-policy.js';

@Injectable()
export class ImagesService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
    @Inject(DatabaseService) private readonly db: DatabaseService,
  ) {}
  onModuleInit() {
    this.timer = setInterval(() => {
      void this.cleanup().catch(() => {});
    }, 3600000);
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  async cleanup() {
    await this.db.query(
      `DELETE FROM community_images WHERE id IN (SELECT i.id FROM community_images i WHERE i.created_at<now()-interval '1 day' AND NOT EXISTS(SELECT 1 FROM post_images pi WHERE pi.image_id=i.id) FOR UPDATE SKIP LOCKED)`,
    );
  }
  async upload(uid: string, post: string, id: string, base64: string) {
    if (base64.length > 2800000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64))
      throw new BadRequestException({ code: 'INVALID_IMAGE' });
    const input = Buffer.from(base64, 'base64');
    const digest = createHash('sha256').update(input).digest('hex');
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const old = (
        await client.query(
          'SELECT firebase_uid,digest,draft_post_id,width,height FROM community_images WHERE id=$1',
          [id],
        )
      ).rows[0];
      if (old) {
        if (
          old.firebase_uid !== uid ||
          old.digest !== digest ||
          old.draft_post_id !== post
        )
          throw new ConflictException({ code: 'POST_CONFLICT' });
        return { id, width: old.width, height: old.height };
      }
      const existingPost = (
        await client.query(
          'SELECT firebase_uid,deleted_at,moderation_status FROM community_posts WHERE id=$1',
          [post],
        )
      ).rows[0];
      if (
        existingPost &&
        (existingPost.firebase_uid !== uid ||
          existingPost.deleted_at ||
          existingPost.moderation_status !== 'visible')
      )
        throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      await client.query(
        `DELETE FROM community_images WHERE id IN (SELECT i.id FROM community_images i WHERE i.created_at<now()-interval '1 day' AND NOT EXISTS(SELECT 1 FROM post_images pi WHERE pi.image_id=i.id) FOR UPDATE SKIP LOCKED)`,
      );
      const quota = (
        await client.query(
          `SELECT count(*) FILTER(WHERE created_at>now()-interval '1 hour')::int AS recent,coalesce(sum(octet_length(bytes)),0)::bigint AS bytes FROM community_images WHERE firebase_uid=$1`,
          [uid],
        )
      ).rows[0];
      if (quota.recent >= 20 || Number(quota.bytes) >= 104857600)
        throw new HttpException({ code: 'IMAGE_LIMIT' }, 429);
      let output;
      try {
        const processor = sharp(input, {
          limitInputPixels: 20000000,
          failOn: 'warning',
        });
        const meta = await processor.metadata();
        if (
          !['jpeg', 'png', 'webp'].includes(meta.format) ||
          (meta.pages ?? 1) > 1
        )
          throw new Error('format');
        output = await processor
          .rotate()
          .resize({
            width: 1600,
            height: 1600,
            fit: 'inside',
            withoutEnlargement: true,
          })
          .flatten({ background: '#ffffff' })
          .jpeg({ quality: 80 })
          .toBuffer({ resolveWithObject: true });
        if (output.data.length > 1048576) throw new Error('size');
      } catch {
        throw new BadRequestException({ code: 'INVALID_IMAGE' });
      }
      await client.query(
        'INSERT INTO community_images(id,draft_post_id,firebase_uid,digest,bytes,width,height) VALUES($1,$2,$3,$4,$5,$6,$7)',
        [
          id,
          post,
          uid,
          digest,
          output.data,
          output.info.width,
          output.info.height,
        ],
      );
      return { id, width: output.info.width, height: output.info.height };
    });
  }
  async image(uid: string, post: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const result = await client.query(
        `SELECT i.bytes,i.width,i.height FROM community_images i JOIN post_images pi ON pi.image_id=i.id
        JOIN ${postRelations} ON r.id=pi.post_id WHERE r.id=$2 AND i.id=$3 AND ${postVisible}`,
        [uid, post, id],
      );
      if (!result.rowCount)
        throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      const image = result.rows[0];
      return {
        id,
        width: image.width,
        height: image.height,
        base64: (image.bytes as Buffer).toString('base64'),
      };
    });
  }
}
