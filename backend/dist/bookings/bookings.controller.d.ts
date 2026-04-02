import { Response } from 'express';
import { BookingsService } from './bookings.service';
import { CreateBookingDto } from './dto/create-booking.dto';
export declare class BookingsController {
    private readonly service;
    constructor(service: BookingsService);
    getFlights(from: string, to: string): Promise<any>;
    getHotels(city: string, checkIn: string, checkOut: string): Promise<any>;
    proxySearchDestinations(body: {
        type: string;
        query: string;
    }): Promise<any>;
    proxySearchHotels(body: any): Promise<any>;
    proxyGetHotelDetails(body: {
        hotelId: string;
    }): Promise<any>;
    proxyGetRoomsAndRates(body: {
        token: string;
        hotelId: string;
        checkIn?: string;
        checkOut?: string;
        rooms?: any[];
    }): Promise<any>;
    proxyGetPaymentUrl(body: any): Promise<any>;
    proxyRevalidateHotel(body: {
        token: string;
        recommendationId: string;
        hotelId: string;
    }): Promise<any>;
    proxyRevalidateFlight(body: {
        fareSourceCode: string;
        key_0: number;
    }): Promise<any>;
    proxyGetFlightPaymentUrl(body: any): Promise<any>;
    proxyGetBookingInfo(body: {
        bookingId: string;
    }): Promise<any>;
    proxyCancelBooking(body: {
        bookingId: string;
    }): Promise<any>;
    imageProxy(url: string, res: Response): Promise<void>;
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
