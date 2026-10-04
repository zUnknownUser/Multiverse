import { BadRequestException } from '@nestjs/common';

export function spaceQuery(q: Record<string, unknown>, keys: string[]) {
  if (
    Object.keys(q).some((k) => !keys.includes(k)) ||
    Object.values(q).some((v) => typeof v !== 'string' || v.length > 120)
  )
    throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
  return q as Record<string, string>;
}
