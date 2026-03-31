import { IsIn, IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class CreateBookingDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsString()
  @IsIn(['flight', 'hotel'])
  type: 'flight' | 'hotel';

  @IsString()
  @IsNotEmpty()
  itemId: string;

  @IsOptional()
  @IsString()
  details?: string;
}
