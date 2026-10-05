import { Transform } from 'class-transformer';
import {
  IsIn,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
} from 'class-validator';
export class ProfileEditDTO {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @Length(1, 80)
  displayName!: string;
  @IsString() @Length(0, 160) bio!: string;
  @IsString() @Matches(/^#[0-9A-Fa-f]{6}$/) avatarColor!: string;
  @IsOptional() @IsIn(['vigilant', 'cosmic', 'robot']) avatarID?: string | null;
  @IsIn(['keep', 'remove', 'replace']) photoAction!:
    'keep' | 'remove' | 'replace';
  @IsOptional() @IsString() @MaxLength(2800000) photo?: string;
}
