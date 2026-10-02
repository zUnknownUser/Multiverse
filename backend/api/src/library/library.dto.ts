import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
export class LibraryMutationDTO {
  @IsUUID('4') mutationID!: string;
  @IsInt() @Min(0) @Max(2147483646) version!: number;
  @IsIn([
    'wanted',
    'favorite',
    'create_list',
    'update_list',
    'delete_list',
    'add_item',
    'remove_item',
  ])
  action!: string;
  @IsOptional() @IsUUID('4') listID?: string;
  @IsOptional() @IsString() @Matches(/^[\w-]{1,120}$/) itemID?: string;
  @IsOptional() @IsBoolean() enabled?: boolean;
  @IsOptional() @IsString() @MaxLength(100) @Matches(/\S/u) title?: string;
  @IsOptional() @IsString() @MaxLength(1000) description?: string;
}
