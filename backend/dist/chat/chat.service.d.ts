import { BookingsService } from '../bookings/bookings.service';
export declare class ChatService {
    private readonly bookingsService;
    private sessions;
    constructor(bookingsService: BookingsService);
    ensureSession(sessionId?: string): string;
    private extractDates;
    private extractLocations;
    private extractCity;
    private validateFlightData;
    private validateHotelData;
    private clearFlightFields;
    private clearHotelFields;
    private setBookingType;
    handleMessage(sessionId: string, message: string): Promise<{
        reply: string;
        booking?: undefined;
        cards?: undefined;
    } | {
        reply: string;
        booking: {
            createdAt: string;
            name: string;
            type: "flight" | "hotel";
            itemId: string;
            details?: string;
            id: string;
        };
        cards?: undefined;
    } | {
        reply: string;
        cards: any;
        booking?: undefined;
    }>;
}
