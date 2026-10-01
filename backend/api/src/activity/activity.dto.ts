import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsISO8601,
  IsString,
  Length,
  Matches,
} from 'class-validator';

export class SaveLogDTO {
  @IsString() @Matches(/^[a-z0-9-]{1,80}$/) itemId!: string;
  @IsISO8601({ strict: true, strictSeparator: true })
  @Matches(/T.+(?:Z|[+-]\d{2}:\d{2})$/)
  loggedAt!: string;
  @IsIn([0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5]) rating!: number;
  @IsBoolean() liked!: boolean;
  @IsBoolean() rewatch!: boolean;
  @IsBoolean() spoiler!: boolean;
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  @IsString()
  @Length(0, 5000)
  text!: string;
}
