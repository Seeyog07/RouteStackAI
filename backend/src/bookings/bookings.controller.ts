import { Body, Controller, Get, Post, HttpCode, HttpStatus, Query, BadRequestException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { SearchHotelsDto } from './dto/search-hotels.dto';

@Controller()
export class BookingsController {
  constructor(private readonly service: BookingsService) {}

  // 1. UPDATED: Now async and accepts origin/destination for dynamic MCP search
  @Get('flights')
  async getFlights(@Query('from') from: string, @Query('to') to: string) {
    if (!from || !to) {
      throw new BadRequestException('Please provide "from" and "to" query parameters');
    }
    return await this.service.findFlights(from, to);
  }

  // 2. UPDATED: Using explicit Query decorators for clarity
  @Get('hotels')
  async getHotels(
    @Query('city') city: string,
    @Query('checkIn') checkIn: string,
    @Query('checkOut') checkOut: string,
  ) {
    if (!city || !checkIn || !checkOut) {
      throw new BadRequestException('Please provide city, checkIn, and checkOut query parameters');
    }
    return await this.service.findHotels(city, checkIn, checkOut);
  }

  // 3. PROXY: Matches your MCP structure
  @Post('mcp/hotel/search-hotels')
  async proxySearchHotels(@Body() body: SearchHotelsDto) {
    const res = await this.service.searchHotels(body);
    return res.body;
  }

  // 4. BOOKING: Standard POST
  @Post('book')
  @HttpCode(HttpStatus.CREATED)
  createBooking(@Body() dto: CreateBookingDto) {
    return this.service.createBooking(dto);
  }

  @Get('bookings')
  listBookings() {
    return this.service.listBookings();
  }
}