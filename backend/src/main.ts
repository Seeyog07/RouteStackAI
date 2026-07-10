import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { Logger, ValidationPipe } from '@nestjs/common';
import * as dotenv from 'dotenv';

dotenv.config();

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('api');
  // Enable CORS so the frontend can call the API from browsers/emulators
  app.enableCors();
  // enable input validation globally
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  const logger = new Logger('Bootstrap');
  logger.log(`Backend listening on http://localhost:${port} (CORS enabled)`);
}

bootstrap();
