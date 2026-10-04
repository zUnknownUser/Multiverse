import { Transform } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsIn,
  IsOptional,
  IsBoolean,
  IsInt,
  IsString,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';

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
  @IsOptional() @IsIn(['vigilant', 'cosmic', 'robot']) avatarID?: string | null;
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
  @ArrayMaxSize(50)
  @ArrayUnique()
  @IsString({ each: true })
  @Matches(/^[a-z0-9-]{1,80}$/, { each: true })
  universeIDs!: string[];
  @IsArray()
  @ArrayMaxSize(500)
  @ArrayUnique()
  @IsString({ each: true })
  @Matches(/^[a-z0-9-]{1,80}$/, { each: true })
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
