import { Body, Controller, Post } from '@nestjs/common';
import { ChatService } from './chat.service';

@Controller('chat')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Post()
  async chat(@Body() body: { sessionId?: string; message: string }) {
    const sessionId = this.chatService.ensureSession(body.sessionId);
    
    // ✅ YOU MUST AWAIT THE RESULT HERE
    const result = await this.chatService.handleMessage(sessionId, body.message || '');
    
    return { sessionId, ...result };
  }
}