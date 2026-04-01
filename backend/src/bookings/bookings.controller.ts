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
  @Post('mcp/hotel/search-destinations')
  async proxySearchDestinations(@Body() body: { type: string; query: string }) {
    const res = await this.service.searchDestinations(body.query);
    return res.body;
  }

  @Post('mcp/hotel/search-hotels')
  async proxySearchHotels(@Body() body: any) {
    const res = await this.service.searchHotels(body);
    return res.body;
  }

  @Post('mcp/hotel/get-hotel-details')
  async proxyGetHotelDetails(@Body() body: { hotelId: string }) {
    const res = await this.service.getHotelDetails(body.hotelId);
    return res.body;
  }

  @Post('mcp/hotel/get-rooms-and-rates')
  async proxyGetRoomsAndRates(@Body() body: { token: string; hotelId: string }) {
    const res = await this.service.getRoomsAndRates(body.token, body.hotelId);
    return res.body;
  }

  @Post('mcp/hotel/get-payment-url')
  async proxyGetPaymentUrl(@Body() body: any) {
    const res = await this.service.getPaymentUrl(body);
    return res.body;
  }

  @Post('mcp/hotel/revalidate')
  async proxyRevalidateHotel(@Body() body: { token: string; recommendationId: string; hotelId: string }) {
    const res = await this.service.revalidateHotel(body.token, body.recommendationId, body.hotelId);
    return res.body;
  }

  @Post('mcp/hotel/get-booking-info')
  async proxyGetBookingInfo(@Body() body: { bookingId: string }) {
    const res = await this.service.getBookingInfo(body.bookingId);
    return res.body;
  }

  @Post('mcp/hotel/cancel-booking')
  async proxyCancelBooking(@Body() body: { bookingId: string }) {
    const res = await this.service.cancelBooking(body.bookingId);
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