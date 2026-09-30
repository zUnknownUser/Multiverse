import { Transform } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsString,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';
import { ITEM_IDS, UNIVERSE_IDS } from './catalog-ids.js';

export class ProfileDTO {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsString()
  @Matches(/^[a-z0-9_.]{3,24}$/)
  username!: string;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @Length(1, 80)
  displayName!: string;
  @IsString() @Matches(/^#[0-9A-Fa-f]{6}$/) avatarColor!: string;
  @IsString() @Length(0, 160) bio!: string;
}
export class UsernameDTO {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsString()
  @Matches(/^[a-z0-9_.]{3,24}$/)
  username!: string;
}
export class OnboardingDTO {
  @IsArray()
  @ArrayMaxSize(3)
  @ArrayUnique()
  @IsIn(UNIVERSE_IDS, { each: true })
  universeIDs!: string[];
  @IsArray()
  @ArrayMaxSize(500)
  @ArrayUnique()
  @IsIn(ITEM_IDS, { each: true })
  seenItemIDs!: string[];
  @IsArray()
  @ArrayMaxSize(100)
  @ArrayUnique()
  @IsString({ each: true })
  @Length(1, 128, { each: true })
  followedUserIDs!: string[];
  @IsInt() @Min(1) @Max(3) step!: number;
  @IsBoolean() completed!: boolean;
  @IsInt() @Min(0) @Max(2147483646) version!: number;
}
