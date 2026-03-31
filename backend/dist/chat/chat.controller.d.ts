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
    } | {
        reply: string;
        cards: any;
        booking?: undefined;
        sessionId: string;
    }>;
}
