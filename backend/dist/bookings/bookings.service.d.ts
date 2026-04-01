import { CreateBookingDto } from './dto/create-booking.dto';
export declare class BookingsService {
    private bookings;
    private locationMap;
    private normalizeLocation;
    findFlights(from: string, to: string, departureDate?: string): Promise<any>;
    findHotels(city: string, checkIn: string, checkOut: string, adults?: number, children?: number): Promise<any>;
    searchDestinations(query: string): Promise<{
        status: any;
        body: any;
    }>;
    revalidateFlight(fareSourceCode: string, key0: number): Promise<any>;
    revalidateHotel(token: string, recommendationId: string, hotelId: string): Promise<any>;
    searchHotels(body: any): Promise<{
        status: any;
        body: any;
    }>;
    getHotelDetails(hotelId: string): Promise<{
        status: any;
        body: any;
    }>;
    getRoomsAndRates(token: string, hotelId: string): Promise<{
        status: any;
        body: any;
    }>;
    getPaymentUrl(params: {
        portalUrl: string;
        priceCheckResult: any;
        correlationId: string;
        hotelName: string;
        checkOut: string;
        checkIn: string;
        recommendationId: string;
        roomId: string;
        token: string;
        hotelId: string;
    }): Promise<{
        status: any;
        body: any;
    }>;
    getBookingInfo(bookingId: string): Promise<{
        status: any;
        body: any;
    }>;
    cancelBooking(bookingId: string): Promise<{
        status: any;
        body: any;
    }>;
    createBooking(dto: CreateBookingDto): {
        createdAt: string;
        name: string;
        type: "flight" | "hotel";
        itemId: string;
        details?: string;
        id: string;
    };
    listBookings(): any[];
    private mcpRequest;
}
