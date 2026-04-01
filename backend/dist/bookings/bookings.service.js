"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.BookingsService = void 0;
const common_1 = require("@nestjs/common");
const crypto = require("crypto");
let BookingsService = class BookingsService {
    constructor() {
        this.bookings = [];
        this.locationMap = {
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
    }
    normalizeLocation(location) {
        const normalized = location.toLowerCase().trim();
        const code = this.locationMap[normalized] || normalized.toUpperCase();
        console.log(`[normalizeLocation] "${location}" → "${normalized}" → "${code}"`);
        return code;
    }
    async findFlights(from, to, departureDate) {
        console.log(`[findFlights] Input: from="${from}", to="${to}", date="${departureDate}"`);
        const fromCode = this.normalizeLocation(from);
        const toCode = this.normalizeLocation(to);
        console.log(`[findFlights] Codes: fromCode="${fromCode}", toCode="${toCode}"`);
        const body = {
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
    async findHotels(city, checkIn, checkOut, adults = 2, children = 0) {
        const dstRes = await this.searchDestinations(city);
        const destinations = dstRes?.body?.result;
        if (!Array.isArray(destinations) || destinations.length === 0) {
            throw new common_1.InternalServerErrorException(`No destination found for city: ${city}`);
        }
        const destination = destinations[0];
        const body = {
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
        const hotelBody = hotelRes?.body ?? hotelRes;
        if (hotelBody?.success === false) {
            console.warn('[findHotels] Hotel API returned failure', hotelBody);
            return hotelBody;
        }
        const token = hotelBody?.result?.token || hotelBody?.token || '';
        const hotels = hotelBody?.result?.result || hotelBody?.result || [];
        if (Array.isArray(hotels) && token) {
            hotels.forEach((hotel) => {
                hotel.token = token;
            });
            console.log(`[findHotels] Attached token to ${hotels.length} hotels`);
        }
        return hotelBody;
    }
    async searchDestinations(query) {
        return await this.mcpRequest('/mcp/hotel/search-destinations', {
            type: 'DESTINATION',
            query,
        });
    }
    async revalidateFlight(fareSourceCode, key0) {
        const res = await this.mcpRequest('/mcp/flight/revalidate', {
            fareSourceCode,
            key_0: key0,
        });
        return res.body;
    }
    async revalidateHotel(token, recommendationId, hotelId) {
        const res = await this.mcpRequest('/mcp/hotel/revalidate', {
            token,
            recommendationId,
            hotelId,
        });
        return res.body;
    }
    async searchHotels(body) {
        return await this.mcpRequest('/mcp/hotel/search-hotels', body);
    }
    async getHotelDetails(hotelId) {
        return await this.mcpRequest('/mcp/hotel/get-hotel-details', { hotelId });
    }
    async getRoomsAndRates(token, hotelId, checkIn, checkOut, rooms) {
        if (!token || token.trim() === '') {
            console.warn('[getRoomsAndRates] Skipping MCP call: token is empty');
            return { body: { success: true, result: { rooms: [] }, message: 'No token provided' } };
        }
        const bodyData = { token, hotelId };
        if (checkIn)
            bodyData.checkIn = checkIn;
        if (checkOut)
            bodyData.checkOut = checkOut;
        if (rooms)
            bodyData.rooms = rooms;
        return await this.mcpRequest('/mcp/hotel/get-rooms-and-rates', bodyData);
    }
    async getPaymentUrl(params) {
        return await this.mcpRequest('/mcp/hotel/get-payment-url', params);
    }
    async getBookingInfo(bookingId) {
        return await this.mcpRequest('/mcp/hotel/get-booking-info', { bookingId });
    }
    async cancelBooking(bookingId) {
        return await this.mcpRequest('/mcp/hotel/cancel-booking', { bookingId });
    }
    createBooking(dto) {
        const id = `b_${Date.now()}`;
        const record = { id, ...dto, createdAt: new Date().toISOString() };
        this.bookings.push(record);
        return record;
    }
    listBookings() {
        return this.bookings;
    }
    async mcpRequest(path, body) {
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
            throw new common_1.InternalServerErrorException('MCP Credentials missing in environment');
        }
        try {
            const ts = Math.floor(Date.now() / 1000);
            const nonce = crypto.randomUUID();
            const hmac = crypto.createHmac('sha256', apiSecret)
                .update(`${apiKey}:${ts}:${nonce}`)
                .digest('base64url');
            console.log('Generated HMAC:', hmac);
            const authRes = await globalThis.fetch(`${BASE_URL}/mcp/auth/partner-token`, {
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
            const dataRes = await globalThis.fetch(`${BASE_URL}${path}`, {
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
        }
        catch (e) {
            console.error('MCP Request Exception:', e.message);
            throw new common_1.InternalServerErrorException(e instanceof Error ? e.message : 'MCP Request failed');
        }
    }
};
exports.BookingsService = BookingsService;
exports.BookingsService = BookingsService = __decorate([
    (0, common_1.Injectable)()
], BookingsService);
//# sourceMappingURL=bookings.service.js.map