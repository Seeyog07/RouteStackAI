import { BookingsService } from './bookings.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { SearchHotelsDto } from './dto/search-hotels.dto';
export declare class BookingsController {
    private readonly service;
    constructor(service: BookingsService);
    getFlights(from: string, to: string): Promise<any>;
    getHotels(city: string, checkIn: string, checkOut: string): Promise<any>;
    proxySearchHotels(body: SearchHotelsDto): Promise<any>;
    createBooking(dto: CreateBookingDto): {
        createdAt: string;
        name: string;
        type: "flight" | "hotel";
        itemId: string;
        details?: string;
        id: string;
    };
    listBookings(): any[];
}
