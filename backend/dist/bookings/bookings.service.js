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
        this.partnerTokenCache = null;
        this.partnerTokenRequest = null;
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
            'tampa': 'TPA',
            'fort lauderdale': 'FLL',
            'jacksonville': 'JAX',
            'austin': 'AUS',
            'san diego': 'SAN',
            'san jose': 'SJC',
            'sacramento': 'SMF',
            'washington dc': 'DCA',
            'washington': 'DCA',
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
        const baseLocation = normalized
            .replace(/\s*\([^)]*\)\s*$/g, '')
            .split(',')[0]
            .split(' - ')[0]
            .trim();
        const mappedCode = this.locationMap[normalized] || this.locationMap[baseLocation];
        if (mappedCode) {
            console.log(`[normalizeLocation] "${location}" → "${baseLocation}" → "${mappedCode}"`);
            return mappedCode;
        }
        if (/^[a-z]{3}$/i.test(baseLocation)) {
            const code = baseLocation.toUpperCase();
            console.log(`[normalizeLocation] "${location}" → "${baseLocation}" → "${code}"`);
            return code;
        }
        console.log(`[normalizeLocation] "${location}" → "${baseLocation}" → invalid`);
        return null;
    }
    titleCaseLocation(value) {
        return value
            .split(' ')
            .filter(Boolean)
            .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
            .join(' ');
    }
    suggestLocations(location, limit = 6) {
        const normalized = location.toLowerCase().trim();
        const baseLocation = normalized
            .replace(/\s*\([^)]*\)\s*$/g, '')
            .split(',')[0]
            .split(' - ')[0]
            .trim();
        const stateSuggestions = {
            florida: ['Miami', 'Orlando', 'Tampa', 'Fort Lauderdale', 'Jacksonville'],
            california: ['Los Angeles', 'San Francisco', 'San Diego', 'San Jose', 'Sacramento'],
            texas: ['Dallas', 'Houston', 'Austin'],
            'new york': ['New York'],
            illinois: ['Chicago'],
            nevada: ['Las Vegas'],
            georgia: ['Atlanta'],
            washington: ['Seattle'],
            massachusetts: ['Boston'],
            arizona: ['Phoenix'],
            colorado: ['Denver'],
            ohio: ['Cleveland', 'Columbus', 'Cincinnati'],
            pennsylvania: ['Philadelphia', 'Pittsburgh'],
            virginia: ['Richmond', 'Norfolk'],
            'new jersey': ['Newark'],
            maryland: ['Baltimore'],
        };
        const seen = new Set();
        const suggestions = [];
        const addSuggestion = (value) => {
            const label = this.titleCaseLocation(value.trim());
            const key = label.toLowerCase();
            if (!label || seen.has(key))
                return;
            seen.add(key);
            suggestions.push(label);
        };
        for (const key of Object.keys(this.locationMap)) {
            const code = this.locationMap[key];
            const matchesQuery = !baseLocation ||
                key.startsWith(baseLocation) ||
                key.includes(baseLocation) ||
                code.toLowerCase().startsWith(baseLocation.replace(/\s+/g, '').slice(0, 3));
            if (matchesQuery) {
                addSuggestion(key);
            }
        }
        for (const [state, cities] of Object.entries(stateSuggestions)) {
            if (baseLocation.includes(state) || state.includes(baseLocation)) {
                for (const city of cities) {
                    addSuggestion(city);
                }
            }
        }
        if (!suggestions.length) {
            ['New York', 'London', 'Los Angeles', 'Chicago', 'Miami', 'Dubai'].forEach(addSuggestion);
        }
        return suggestions.slice(0, limit);
    }
    async findFlights(from, to, departureDate) {
        console.log(`[findFlights] Input: from="${from}", to="${to}", date="${departureDate}"`);
        const fromCode = this.normalizeLocation(from);
        const toCode = this.normalizeLocation(to);
        console.log(`[findFlights] Codes: fromCode="${fromCode}", toCode="${toCode}"`);
        if (!fromCode || !toCode) {
            const invalidValue = !fromCode ? from : to;
            const invalidField = !fromCode ? 'from' : 'to';
            return {
                success: false,
                code: 'INVALID_LOCATION',
                message: !fromCode && !toCode
                    ? 'Please provide both a departure city or airport and a destination city or airport. For example: London to Miami.'
                    : !fromCode
                        ? `I could not recognize "${from}" as a valid departure city or airport. Please provide a city or 3-letter airport code.`
                        : `I could not recognize "${to}" as a valid destination city or airport. Please provide a city or 3-letter airport code.`,
                field: invalidField,
                suggestions: this.suggestLocations(String(invalidValue ?? '')),
            };
        }
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
        }, process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai', process.env.MCP_BASE_URL);
        return res.body;
    }
    async getFlightPaymentUrl(params) {
        const selectedFlight = params.selectedFlight?.rawFlight || params.selectedFlight || {};
        const flightPayload = selectedFlight || params.revalidateResult?.flight || params.priceCheckResult?.flight || {};
        const firstLeg = Array.isArray(selectedFlight?.flights) && selectedFlight.flights.length
            ? selectedFlight.flights[0]
            : undefined;
        const origin = params.origin ||
            selectedFlight?.departureCode ||
            selectedFlight?.origin ||
            firstLeg?.departure ||
            '';
        const destination = params.destination ||
            selectedFlight?.arrivalCode ||
            selectedFlight?.destination ||
            firstLeg?.arrival ||
            '';
        const departureRaw = params.departureDate ||
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
        const res = await this.mcpRequest('/mcp/flight/get-payment-url', body, process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai', process.env.MCP_BASE_URL);
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
    async getHotelDetailsAndRates(params) {
        const bodyData = {
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
        return await this.mcpRequest('/mcp/hotel/get-booking-info', { bookingId }, process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai', process.env.MCP_BASE_URL);
    }
    async cancelBooking(bookingId) {
        return await this.mcpRequest('/mcp/hotel/cancel-booking', { bookingId }, process.env.MCP_EVOLVE_BASE_URL || 'https://evolvemcp.routestack.ai', process.env.MCP_BASE_URL);
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
    async mcpRequest(path, body, baseUrl, authBaseUrl) {
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
            throw new common_1.InternalServerErrorException('MCP Credentials missing in environment');
        }
        const resolvedApiKey = apiKey;
        const resolvedApiSecret = apiSecret;
        const resolvedBaseUrl = BASE_URL;
        const resolvedAuthBaseUrl = AUTH_BASE_URL;
        try {
            const token = await this.getPartnerToken(resolvedApiKey, resolvedApiSecret, resolvedAuthBaseUrl, resolvedBaseUrl);
            let dataRes = await globalThis.fetch(`${resolvedBaseUrl}${path}`, {
                method: 'POST',
                headers: this.buildMcpAuthHeaders(token, resolvedApiKey),
                body: JSON.stringify(body),
            });
            if (dataRes.status === 401 || dataRes.status === 403) {
                console.warn('MCP data request unauthorized, refreshing partner token and retrying once.');
                this.invalidatePartnerToken(resolvedBaseUrl, resolvedAuthBaseUrl, resolvedApiKey);
                const refreshedToken = await this.getPartnerToken(resolvedApiKey, resolvedApiSecret, resolvedAuthBaseUrl, resolvedBaseUrl);
                dataRes = await globalThis.fetch(`${resolvedBaseUrl}${path}`, {
                    method: 'POST',
                    headers: this.buildMcpAuthHeaders(refreshedToken, resolvedApiKey),
                    body: JSON.stringify(body),
                });
            }
            const data = await dataRes.json();
            console.log('MCP Response Status:', dataRes.status);
            console.log('--- MCP Debug End ---');
            return { status: dataRes.status, body: data };
        }
        catch (e) {
            const errorMessage = e instanceof Error ? e.message : 'MCP Request failed';
            console.error('MCP Request Exception:', errorMessage);
            throw new common_1.InternalServerErrorException(errorMessage);
        }
    }
    invalidatePartnerToken(baseUrl, authBaseUrl, apiKey) {
        if (this.partnerTokenCache &&
            this.partnerTokenCache.baseUrl === baseUrl &&
            this.partnerTokenCache.authBaseUrl === authBaseUrl &&
            this.partnerTokenCache.apiKey === apiKey) {
            this.partnerTokenCache = null;
        }
    }
    async getPartnerToken(apiKey, apiSecret, authBaseUrl, baseUrl) {
        const now = Date.now();
        if (this.partnerTokenCache &&
            this.partnerTokenCache.baseUrl === baseUrl &&
            this.partnerTokenCache.authBaseUrl === authBaseUrl &&
            this.partnerTokenCache.apiKey === apiKey &&
            this.partnerTokenCache.expiresAt > now) {
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
            const authRes = await globalThis.fetch(`${authBaseUrl}/mcp/auth/partner-token`, {
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
        }
        finally {
            this.partnerTokenRequest = null;
        }
    }
    buildMcpAuthHeaders(token, apiKey) {
        const normalizedToken = this.normalizePartnerToken(token);
        return {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${normalizedToken}`,
            'x-partner-token': normalizedToken,
            'x-api-key': apiKey,
        };
    }
    normalizePartnerToken(token) {
        return token.replace(/^Bearer\s+/i, '').trim();
    }
    extractPartnerToken(authBody) {
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
};
exports.BookingsService = BookingsService;
exports.BookingsService = BookingsService = __decorate([
    (0, common_1.Injectable)()
], BookingsService);
//# sourceMappingURL=bookings.service.js.map