import { ChatService } from './chat.service';
export declare class ChatController {
    private readonly chatService;
    constructor(chatService: ChatService);
    chat(body: {
        sessionId?: string;
        message: string;
    }): Promise<{
        reply: string;
        booking?: undefined;
        suggestions?: undefined;
        suggestionField?: undefined;
        cards?: undefined;
        sessionId: string;
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
        suggestions?: undefined;
        suggestionField?: undefined;
        cards?: undefined;
        sessionId: string;
        checkIn?: undefined;
        checkOut?: undefined;
    } | {
        reply: any;
        suggestions: any;
        suggestionField: string;
        booking?: undefined;
        cards?: undefined;
        sessionId: string;
        checkIn?: undefined;
        checkOut?: undefined;
    } | {
        reply: string;
        cards: any;
        booking?: undefined;
        suggestions?: undefined;
        suggestionField?: undefined;
        sessionId: string;
        checkIn?: undefined;
        checkOut?: undefined;
    } | {
        sessionId: string;
        reply: string;
        checkIn: string;
        checkOut: string;
        cards: any;
        booking?: undefined;
        suggestions?: undefined;
        suggestionField?: undefined;
    }>;
}
