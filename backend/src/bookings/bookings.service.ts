import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { CreateBookingDto } from './dto/create-booking.dto';
import * as crypto from 'crypto';

type SearchBody = { city: string; checkIn: string; checkOut: string };

@Injectable()
export class BookingsService {
  private bookings: any[] = [];

  // Location code mapping (city name → airport code)
  private locationMap: { [key: string]: string } = {
    // Major US Airports
    'new york': 'JFK',
    'nyc': 'JFK',
    'ny': 'JFK',
    'los angeles': 'LAX',
    'la': 'LAX',
    'chicago': 'ORD',
    'san francisco': 'SFO',
    'sf': 'SFO',
    'boston': 'BOS',
    'miami': 'MIA',
    'denver': 'DEN',
    'seattle': 'SEA',
    'atlanta': 'ATL',
    'orlando': 'MCO',
    'las vegas': 'LAS',
    'vegas': 'LAS',
    'dallas': 'DFW',
    'houston': 'IAH',
    
    // Major International Airports
    'london': 'LHR',
    'paris': 'CDG',
    'tokyo': 'NRT',
    'sydney': 'SYD',
    'dubai': 'DXB',
    'mumbai': 'BOM',
    'delhi': 'DEL',
    'singapore': 'SIN',
    'hong kong': 'HKG',
    'bangkok': 'BKK',
    'amsterdam': 'AMS',
    'frankfurt': 'FRA',
    'toronto': 'YYZ',
    'mexico city': 'MEX',
    'cancun': 'CUN',
    'sao paulo': 'GIG',
    'buenos aires': 'EZE',
    'cairo': 'CAI',
    'johannesburg': 'JNB',
  };

  private normalizeLocation(location: string): string {
    const normalized = location.toLowerCase().trim();
    const code = this.locationMap[normalized] || normalized.toUpperCase();
    console.log(`[normalizeLocation] "${location}" → "${normalized}" → "${code}"`);
    return code;
  }

  // 1. Dynamic Flight Search
  async findFlights(from: string, to: string, departureDate?: string) {
    console.log(`[findFlights] Input: from="${from}", to="${to}", date="${departureDate}"`);
    
    const fromCode = this.normalizeLocation(from);
    const toCode = this.normalizeLocation(to);

    console.log(`[findFlights] Codes: fromCode="${fromCode}", toCode="${toCode}"`);

    // Try with origin / destination (RouteStack likely uses these)
    const body: any = { 
      origin: fromCode, 
      destination: toCode 
    };
    if (departureDate) {
      body.departureDate = departureDate;
    }
    
    console.log(`[findFlights] API Request body:`, JSON.stringify(body));
    
    const res = await this.mcpRequest('/mcp/flight/search', body);
    console.log("Checking flights:", res.body);
    return res.body;
  }

  // 2. Dynamic Hotel Search (orchestrated)
  async findHotels(city: string, checkIn: string, checkOut: string, adults = 2, children = 0) {
    // 2.1 Find destination by city
    const dstRes = await this.searchDestinations(city);
    const destinations = dstRes?.body?.result;

    if (!Array.isArray(destinations) || destinations.length === 0) {
      throw new InternalServerErrorException(`No destination found for city: ${city}`);
    }

    const destination = destinations[0];
    const body: any = {
      currency: 'USD',
      long: destination.coordinates?.long ?? 0,
      lat: destination.coordinates?.lat ?? 0,
      rooms: [
        {
          childAges: [],
          children,
          adults,
        },
      ],
      checkOut,
      checkIn,
      destinationId: destination.id,
    };

    const hotelRes = await this.searchHotels(body);

    // Widen hotel result processed shape for downstream handling.
    const hotelBody = hotelRes?.body ?? hotelRes;
    if (hotelBody?.success === false) {
      console.warn('[findHotels] Hotel API returned failure', hotelBody);
      return hotelBody;
    }

    return hotelBody;
  }

  async searchDestinations(query: string) {
    return await this.mcpRequest('/mcp/hotel/search-destinations', {
      type: 'DESTINATION',
      query,
    });
  }

  // 2.1 Revalidate flight after selection
  async revalidateFlight(fareSourceCode: string, key0: number) {
    const res = await this.mcpRequest('/mcp/flight/revalidate', {
      fareSourceCode,
      key_0: key0,
    });
    return res.body;
  }

  async revalidateHotel(token: string, recommendationId: string, hotelId: string) {
    const res = await this.mcpRequest('/mcp/hotel/revalidate', {
      token,
      recommendationId,
      hotelId,
    });
    return res.body;
  }

  async searchHotels(body: any) {
    return await this.mcpRequest('/mcp/hotel/search-hotels', body);
  }

  async getHotelDetails(hotelId: string) {
    return await this.mcpRequest('/mcp/hotel/get-hotel-details', { hotelId });
  }

  async getRoomsAndRates(token: string, hotelId: string) {
    return await this.mcpRequest('/mcp/hotel/get-rooms-and-rates', { token, hotelId });
  }

  async getPaymentUrl(params: {
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
  }) {
    return await this.mcpRequest('/mcp/hotel/get-payment-url', params);
  }

  async getBookingInfo(bookingId: string) {
    return await this.mcpRequest('/mcp/hotel/get-booking-info', { bookingId });
  }

  async cancelBooking(bookingId: string) {
    return await this.mcpRequest('/mcp/hotel/cancel-booking', { bookingId });
  }

  // 4. Booking Management
  createBooking(dto: CreateBookingDto) {
    const id = `b_${Date.now()}`;
    const record = { id, ...dto, createdAt: new Date().toISOString() };
    this.bookings.push(record);
    return record;
  }

  // 5. List Bookings (Fixed missing method)
  listBookings() {
    return this.bookings;
  }

  // 6. Private Helper for MCP API Calls
  private async mcpRequest(path: string, body: any) {
  // 1. Log Environment Variables at the start
  console.log('--- MCP Debug Start ---');
  console.log('BASE_URL:', process.env.MCP_BASE_URL);
  console.log('API_KEY:', process.env.MCP_API_KEY ? '✅ Loaded' : '❌ MISSING');
  console.log('API_SECRET:', process.env.MCP_API_SECRET ? '✅ Loaded' : '❌ MISSING');
  console.log('Request Path:', path);
  console.log('Request Body:', JSON.stringify(body));

  const BASE_URL = process.env.MCP_BASE_URL;
  const apiKey = process.env.MCP_API_KEY;
  const apiSecret = process.env.MCP_API_SECRET;

  if (!apiSecret || !apiKey || !BASE_URL) {
    console.error('CRITICAL: Environment variables are missing!');
    throw new InternalServerErrorException('MCP Credentials missing in environment');
  }

  try {
    const ts = Math.floor(Date.now() / 1000);
    const nonce = crypto.randomUUID();
    const hmac = crypto.createHmac('sha256', apiSecret)
      .update(`${apiKey}:${ts}:${nonce}`)
      .digest('base64url');

    console.log('Generated HMAC:', hmac);

    // Auth Token Step
    const authRes = await (globalThis as any).fetch(`${BASE_URL}/mcp/auth/partner-token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce }),
    });

    if (!authRes.ok) {
      const errorText = await authRes.text();
      console.error(`Auth Step Failed: ${authRes.status}`, errorText);
      throw new Error(`Auth failed: ${authRes.status}`);
    }

    const { token } = await authRes.json();
    console.log('Auth Token Received: ✅');

    // Search Data Step
    const dataRes = await (globalThis as any).fetch(`${BASE_URL}${path}`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json', 
        'Authorization': `Bearer ${token}` 
      },
      body: JSON.stringify(body),
    });

    const data = await dataRes.json();
    console.log('MCP Response Status:', dataRes.status);
    console.log('--- MCP Debug End ---');

    return { status: dataRes.status, body: data };
  } catch (e) {
    console.error('MCP Request Exception:', e.message);
    throw new InternalServerErrorException(e instanceof Error ? e.message : 'MCP Request failed');
  }
}
}