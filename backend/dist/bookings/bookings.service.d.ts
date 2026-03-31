import { CreateBookingDto } from './dto/create-booking.dto';
type SearchBody = {
    city: string;
    checkIn: string;
    checkOut: string;
};
export declare class BookingsService {
    private bookings;
    private locationMap;
    private normalizeLocation;
    findFlights(from: string, to: string, departureDate?: string): Promise<any>;
    findHotels(city: string, checkIn: string, checkOut: string): Promise<any>;
    revalidateFlight(fareSourceCode: string, key0: number): Promise<any>;
    searchHotels(body: SearchBody): Promise<{
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
export {};
