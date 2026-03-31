import { IsString, IsNotEmpty, Matches } from 'class-validator';

export class SearchHotelsDto {
  @IsString()
  @IsNotEmpty()
  city: string;

  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'checkIn must be YYYY-MM-DD' })
  checkIn: string;

  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'checkOut must be YYYY-MM-DD' })
  checkOut: string;
}
