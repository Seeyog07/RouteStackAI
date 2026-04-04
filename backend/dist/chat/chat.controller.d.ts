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
        cards?: undefined;
        sessionId: string;
        checkIn?: undefined;
        checkOut?: undefined;
    } | {
        reply: string;
        cards: any;
        booking?: undefined;
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
    }>;
}
