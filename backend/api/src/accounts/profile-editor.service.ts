import {
  BadRequestException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { AccountLifecycleService } from './account-lifecycle.service.js';
import { unblocked } from '../social/social-policy.js';
import type { ProfileEditDTO } from './profile-editor.dto.js';

@Injectable()
export class ProfileEditorService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
  ) {}
  async save(uid: string, input: ProfileEditDTO) {
    let bytes: Buffer | undefined;
    if (input.photoAction === 'replace') {
      if (!input.photo || !/^[A-Za-z0-9+/]+={0,2}$/.test(input.photo))
        throw new BadRequestException({ code: 'INVALID_IMAGE' });
      try {
        const image = sharp(Buffer.from(input.photo, 'base64'), {
          limitInputPixels: 20000000,
          failOn: 'warning',
        });
        const meta = await image.metadata();
        if (
          !['jpeg', 'png', 'webp'].includes(meta.format) ||
          (meta.pages ?? 1) > 1
        )
          throw new Error('format');
        bytes = await image
          .rotate()
          .resize(512, 512, { fit: 'cover' })
          .flatten({ background: '#F5F1E8' })
          .jpeg({ quality: 82 })
          .toBuffer();
        if (bytes.length > 262144) throw new Error('size');
      } catch {
        throw new BadRequestException({ code: 'INVALID_IMAGE' });
      }
    } else if (input.photo != null) {
      throw new BadRequestException({ code: 'INVALID_IMAGE' });
    }
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      const current = (
        await c.query(
          'SELECT * FROM profiles WHERE firebase_uid=$1 AND deletion_requested_at IS NULL FOR UPDATE',
          [uid],
        )
      ).rows[0];
      if (!current) throw new NotFoundException({ code: 'PROFILE_REQUIRED' });
      let photoID = current.avatar_photo_id;
      if (input.photoAction !== 'keep') {
        // Drop the reference before replacing the unique image ID; old URLs stop resolving.
        await c.query(
          'UPDATE profiles SET avatar_photo_id=NULL WHERE firebase_uid=$1',
          [uid],
        );
        await c.query('DELETE FROM profile_photos WHERE firebase_uid=$1', [
          uid,
        ]);
        photoID = null;
        if (bytes) {
          photoID = randomUUID();
          await c.query(
            'INSERT INTO profile_photos(firebase_uid,id,bytes) VALUES($1,$2,$3)',
            [uid, photoID, bytes],
          );
        }
      }
      const row = (
        await c.query(
          `UPDATE profiles SET display_name=$2,bio=$3,avatar_color=$4,avatar_id=$5,avatar_photo_id=$6,updated_at=now() WHERE firebase_uid=$1 RETURNING *`,
          [
            uid,
            input.displayName,
            input.bio,
            input.avatarColor,
            photoID ? null : (input.avatarID ?? null),
            photoID,
          ],
        )
      ).rows[0];
      return {
        userID: uid,
        username: row.username,
        displayName: row.display_name,
        bio: row.bio,
        avatarColor: row.avatar_color,
        avatarID: row.avatar_id,
        avatarPhotoID: row.avatar_photo_id,
      };
    });
  }
  async photo(uid: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      const row = (
        await c.query(
          `SELECT ph.bytes FROM profile_photos ph JOIN profiles p USING(firebase_uid)
        WHERE ph.id=$2 AND p.avatar_photo_id=ph.id AND p.deletion_requested_at IS NULL
        AND (p.firebase_uid=$1 OR (EXISTS(SELECT 1 FROM onboarding viewer WHERE viewer.firebase_uid=$1 AND viewer.completed) AND EXISTS(SELECT 1 FROM onboarding o WHERE o.firebase_uid=p.firebase_uid AND o.completed) AND ${unblocked('$1', 'p.firebase_uid')}))`,
          [uid, id],
        )
      ).rows[0];
      if (!row) throw new NotFoundException({ code: 'PERSON_UNAVAILABLE' });
      return { id, base64: (row.bytes as Buffer).toString('base64') };
    });
  }
}
