import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config'; // 1. Import the ConfigModule
import { BookingsModule } from './bookings/bookings.module';
import { ChatModule } from './chat/chat.module';

@Module({
  imports: [
    // 2. Add ConfigModule.forRoot()
    ConfigModule.forRoot({
      isGlobal: true, // This makes variables available in BookingsService without extra imports
      envFilePath: '.env', // Optional: explicitly point to the file (defaults to .env)
    }),
    BookingsModule, 
    ChatModule
  ],
})
export class AppModule {}