import { BookingsService } from '../bookings/bookings.service';
export declare class ChatService {
    private readonly bookingsService;
    private sessions;
    constructor(bookingsService: BookingsService);
    ensureSession(sessionId?: string): string;
    private getOrCreateSession;
    private addConversationTurn;
    recordAssistantReply(sessionId: string, reply?: string): void;
    private getCompactHistory;
    private normalizeIsoDate;
    private sanitizeLlmTextValue;
    private sanitizeLlmInterpretation;
    private mergeLlmInterpretation;
    private parseLlmJson;
    private inferBookingContextWithLlm;
    private extractDates;
    private isValidDateParts;
    private toIsoFromParts;
    private parseSlashDateMatch;
    private parseMonthNameDate;
    private toIsoDate;
    private getNextWeekday;
    private extractRelativeDate;
    private sanitizeLocationCandidate;
    private isPastIsoDate;
    private hasPotentialDateMention;
    private extractLocations;
    private extractCity;
    private validateFlightData;
    private validateHotelData;
    private clearFlightFields;
    private clearHotelFields;
    private setBookingType;
    private isBookingInfoRequest;
    private isCancelBookingRequest;
    private extractBookingId;
    handleMessage(sessionId: string, message: string): Promise<{
        reply: string;
        booking?: undefined;
        cards?: undefined;
        sessionId?: undefined;
        checkIn?: undefined;
        checkOut?: undefined;
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
        sessionId?: undefined;
        checkIn?: undefined;
        checkOut?: undefined;
    } | {
        reply: string;
        cards: any;
        booking?: undefined;
        sessionId?: undefined;
        checkIn?: undefined;
        checkOut?: undefined;
    } | {
        sessionId: string;
        reply: string;
        checkIn: string;
        checkOut: string;
        cards: any;
        booking?: undefined;
    }>;
}
