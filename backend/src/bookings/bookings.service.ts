import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { CreateBookingDto } from './dto/create-booking.dto';
import * as crypto from 'crypto';

type SearchBody = { city: string; checkIn: string; checkOut: string };

@Injectable()
export class BookingsService {
  private bookings: any[] = [];
  private partnerTokenCache: {
    token: string;
    expiresAt: number;
    baseUrl: string;
    authBaseUrl: string;
    apiKey: string;
  } | null = null;
  private partnerTokenRequest: Promise<string> | null = null;

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

    // Extract token from MCP response and attach to each hotel
    const token = hotelBody?.result?.token || hotelBody?.token || '';
    const hotels = hotelBody?.result?.result || hotelBody?.result || [];
    
    if (Array.isArray(hotels) && token) {
      hotels.forEach((hotel: any) => {
        hotel.token = token;
      });
      console.log(`[findHotels] Attached token to ${hotels.length} hotels`);
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
    const res = await this.mcpRequest(
      '/mcp/flight/revalidate',
      {
        fareSourceCode,
        key_0: key0,
      },
      process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai',
      process.env.MCP_BASE_URL,
    );
    return res.body;
  }

  async getFlightPaymentUrl(params: {
    fareSourceCode: string;
    key_0?: number;
    key0?: number;
    revalidateResult?: any;
    priceCheckResult?: any;
    selectedFlight?: any;
    portalUrl?: string;
    origin?: string;
    destination?: string;
    departureDate?: string;
  }) {
    const selectedFlight = params.selectedFlight?.rawFlight || params.selectedFlight || {};
    const flightPayload =
      selectedFlight || params.revalidateResult?.flight || params.priceCheckResult?.flight || {};

    const firstLeg = Array.isArray(selectedFlight?.flights) && selectedFlight.flights.length
      ? selectedFlight.flights[0]
      : undefined;

    const origin =
      params.origin ||
      selectedFlight?.departureCode ||
      selectedFlight?.origin ||
      firstLeg?.departure ||
      '';

    const destination =
      params.destination ||
      selectedFlight?.arrivalCode ||
      selectedFlight?.destination ||
      firstLeg?.arrival ||
      '';

    const departureRaw =
      params.departureDate ||
      selectedFlight?.departure ||
      selectedFlight?.departureDate ||
      firstLeg?.departureTime ||
      firstLeg?.departureDate ||
      '';

    const departureDate = /^\d{4}-\d{2}-\d{2}$/.test(departureRaw)
      ? departureRaw
      : (typeof departureRaw === 'string' && departureRaw.includes('T')
          ? departureRaw.split('T')[0]
          : departureRaw);

    const key_0 = Number(params.key_0 ?? params.key0 ?? 0);

    const body = {
      fareSourceCode: params.fareSourceCode,
      key_0,
      key0: key_0,
      portalUrl: params.portalUrl || 'https://routestack.ai',
      revalidateResult: params.revalidateResult,
      priceCheckResult: params.priceCheckResult || params.revalidateResult,
      selectedFlight: selectedFlight,
      flight: flightPayload,
      origin,
      destination,
      departureDate,
    };

    const res = await this.mcpRequest(
      '/mcp/flight/get-payment-url',
      body,
      process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai',
      process.env.MCP_BASE_URL,
    );
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

  async getHotelDetailsAndRates(params: {
    hotelId: string;
    token: string;
    checkIn: string;
    checkOut: string;
    rooms: any[];
    correlationId?: string;
  }) {
    const bodyData: any = {
      hotelId: params.hotelId,
      token: params.token,
      checkIn: params.checkIn,
      checkOut: params.checkOut,
      rooms: params.rooms,
    };
    if (params.correlationId) {
      bodyData.correlationId = params.correlationId;
    }

    return await this.mcpRequest('/mcp/hotel/get-hotel-details-and-rates', bodyData);
  }

  async getRoomsAndRates(token: string, hotelId: string, checkIn?: string, checkOut?: string, rooms?: any[]) {
    // If no token, return empty result gracefully to avoid auth rate limiting
    if (!token || token.trim() === '') {
      console.warn('[getRoomsAndRates] Skipping MCP call: token is empty');
      return { body: { success: true, result: { rooms: [] }, message: 'No token provided' } };
    }

    const bodyData: any = { token, hotelId };
    if (checkIn) bodyData.checkIn = checkIn;
    if (checkOut) bodyData.checkOut = checkOut;
    if (rooms) bodyData.rooms = rooms;
    return await this.mcpRequest('/mcp/hotel/get-rooms-and-rates', bodyData);
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
    return await this.mcpRequest(
      '/mcp/hotel/get-booking-info',
      { bookingId },
      process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai',
      process.env.MCP_BASE_URL,
    );
  }

  async cancelBooking(bookingId: string) {
    return await this.mcpRequest(
      '/mcp/hotel/cancel-booking',
      { bookingId },
      process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai',
      process.env.MCP_BASE_URL,
    );
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
  private async mcpRequest(path: string, body: any, baseUrl?: string, authBaseUrl?: string) {
  // 1. Log Environment Variables at the start
  console.log('--- MCP Debug Start ---');
  console.log('BASE_URL:', baseUrl || process.env.MCP_BASE_URL);
  console.log('AUTH_BASE_URL:', authBaseUrl || baseUrl || process.env.MCP_BASE_URL);
  console.log('API_KEY:', process.env.MCP_API_KEY ? '✅ Loaded' : '❌ MISSING');
  console.log('API_SECRET:', process.env.MCP_API_SECRET ? '✅ Loaded' : '❌ MISSING');
  console.log('Request Path:', path);
  console.log('Request Body:', JSON.stringify(body));

  const BASE_URL = baseUrl || process.env.MCP_BASE_URL;
  const AUTH_BASE_URL = authBaseUrl || BASE_URL;
  const apiKey = process.env.MCP_API_KEY;
  const apiSecret = process.env.MCP_API_SECRET;

  if (!apiSecret || !apiKey || !BASE_URL) {
    console.error('CRITICAL: Environment variables are missing!');
    throw new InternalServerErrorException('MCP Credentials missing in environment');
  }

  const resolvedApiKey = apiKey as string;
  const resolvedApiSecret = apiSecret as string;
  const resolvedBaseUrl = BASE_URL as string;
  const resolvedAuthBaseUrl = AUTH_BASE_URL as string;

  try {
    const token = await this.getPartnerToken(resolvedApiKey, resolvedApiSecret, resolvedAuthBaseUrl, resolvedBaseUrl);

    let dataRes = await (globalThis as any).fetch(`${resolvedBaseUrl}${path}`, {
      method: 'POST',
      headers: this.buildMcpAuthHeaders(token, resolvedApiKey),
      body: JSON.stringify(body),
    });

    if (dataRes.status === 401 || dataRes.status === 403) {
      console.warn('MCP data request unauthorized, refreshing partner token and retrying once.');
      this.invalidatePartnerToken(resolvedBaseUrl, resolvedAuthBaseUrl, resolvedApiKey);
      const refreshedToken = await this.getPartnerToken(resolvedApiKey, resolvedApiSecret, resolvedAuthBaseUrl, resolvedBaseUrl);
      dataRes = await (globalThis as any).fetch(`${resolvedBaseUrl}${path}`, {
        method: 'POST',
        headers: this.buildMcpAuthHeaders(refreshedToken, resolvedApiKey),
        body: JSON.stringify(body),
      });
    }

    const data = await dataRes.json();
    console.log('MCP Response Status:', dataRes.status);
    console.log('--- MCP Debug End ---');

    return { status: dataRes.status, body: data };
  } catch (e) {
    const errorMessage = e instanceof Error ? e.message : 'MCP Request failed';
    console.error('MCP Request Exception:', errorMessage);
    throw new InternalServerErrorException(errorMessage);
  }
}

  private invalidatePartnerToken(baseUrl: string, authBaseUrl: string, apiKey: string) {
    if (
      this.partnerTokenCache &&
      this.partnerTokenCache.baseUrl === baseUrl &&
      this.partnerTokenCache.authBaseUrl === authBaseUrl &&
      this.partnerTokenCache.apiKey === apiKey
    ) {
      this.partnerTokenCache = null;
    }
  }

  private async getPartnerToken(
    apiKey: string,
    apiSecret: string,
    authBaseUrl: string,
    baseUrl: string,
  ): Promise<string> {
    const now = Date.now();
    if (
      this.partnerTokenCache &&
      this.partnerTokenCache.baseUrl === baseUrl &&
      this.partnerTokenCache.authBaseUrl === authBaseUrl &&
      this.partnerTokenCache.apiKey === apiKey &&
      this.partnerTokenCache.expiresAt > now
    ) {
      return this.partnerTokenCache.token;
    }

    if (this.partnerTokenRequest) {
      return await this.partnerTokenRequest;
    }

    this.partnerTokenRequest = (async () => {
      const ts = Math.floor(Date.now() / 1000);
      const nonce = crypto.randomUUID();
      const hmac = crypto
        .createHmac('sha256', apiSecret)
        .update(`${apiKey}:${ts}:${nonce}`)
        .digest('base64url');

      console.log('Generated HMAC:', hmac);

      const authRes = await (globalThis as any).fetch(`${authBaseUrl}/mcp/auth/partner-token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ apiKey, hmac, timestamp: ts, nonce }),
      });

      if (!authRes.ok) {
        const errorText = await authRes.text();
        console.error(`Auth Step Failed: ${authRes.status}`, errorText);

        if (this.partnerTokenCache && this.partnerTokenCache.expiresAt > Date.now()) {
          console.warn('Auth failed, using cached partner token.');
          return this.partnerTokenCache.token;
        }

        throw new Error(`Auth failed: ${authRes.status}`);
      }

      const authBody = await authRes.json();
      console.log('Auth Response Keys:', Object.keys(authBody || {}));
      const token = this.extractPartnerToken(authBody);

      if (!token) {
        throw new Error('Auth failed: missing token in response');
      }

      this.partnerTokenCache = {
        token,
        expiresAt: Date.now() + 10 * 60 * 1000,
        baseUrl,
        authBaseUrl,
        apiKey,
      };

      console.log('Auth Token Received: ✅');
      return token;
    })();

    try {
      return await this.partnerTokenRequest;
    } finally {
      this.partnerTokenRequest = null;
    }
  }

  private buildMcpAuthHeaders(token: string, apiKey: string): Record<string, string> {
    const normalizedToken = this.normalizePartnerToken(token);
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${normalizedToken}`,
      'x-partner-token': normalizedToken,
      'x-api-key': apiKey,
    };
  }

  private normalizePartnerToken(token: string): string {
    return token.replace(/^Bearer\s+/i, '').trim();
  }

  private extractPartnerToken(authBody: any): string | null {
    const candidates = [
      authBody?.token,
      authBody?.accessToken,
      authBody?.partnerToken,
      authBody?.data?.token,
      authBody?.data?.accessToken,
      authBody?.result?.token,
      authBody?.result?.accessToken,
    ];

    for (const candidate of candidates) {
      if (typeof candidate === 'string' && candidate.trim()) {
        return this.normalizePartnerToken(candidate);
      }
    }

    return null;
  }
}