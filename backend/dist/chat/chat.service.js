"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChatService = void 0;
const common_1 = require("@nestjs/common");
const bookings_service_1 = require("../bookings/bookings.service");
let ChatService = class ChatService {
    constructor(bookingsService) {
        this.bookingsService = bookingsService;
        this.sessions = new Map();
    }
    ensureSession(sessionId) {
        const id = sessionId || `s_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
        if (!this.sessions.has(id)) {
            this.sessions.set(id, {
                state: 'idle',
                bookingType: undefined,
            });
        }
        return id;
    }
    extractDates(text) {
        const dateRegex = /\d{4}-\d{2}-\d{2}/g;
        return text.match(dateRegex) || [];
    }
    extractLocations(text) {
        const cleanedInput = text
            .replace(/\b(?:book|a|an|flight|flights|fly|please|search|find)\b/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();
        let fromToRegex = /(?:from|departure|origin|starting?\s+(?:from|at))\s+([a-z\s]+?)(?:\s+to\s+|\s+and\s+|\s*→\s*|\s*-\s*)([a-z\s]+?)(?:\s+on|\s+in|\s+for|\s+with|$|\.|,)/i;
        let match = cleanedInput.match(fromToRegex);
        if (match) {
            console.log('[extractLocations] Pattern 1 matched:', match[1], '→', match[2]);
            return { from: match[1].trim(), to: match[2].trim() };
        }
        fromToRegex = /([a-z\s]+?)\s+to\s+([a-z\s]+?)(?:\s+on|\s+in|\s+for|\s+with|$|\.|,)/i;
        match = cleanedInput.match(fromToRegex);
        if (match) {
            const firstPart = match[1].toLowerCase();
            if (!['talk', 'speak', 'say', 'tell', 'listen'].includes(firstPart)) {
                console.log('[extractLocations] Pattern 2 matched:', match[1], '→', match[2]);
                return { from: match[1].trim(), to: match[2].trim() };
            }
        }
        console.log('[extractLocations] No patterns matched. Input:', text);
        return {};
    }
    extractCity(text) {
        const cityCountryRegex = /(?:hotel\s+in|stay\s+in|room\s+in|at|in)\s+([a-z\s]+?)(?:\s*,\s*|\s+in\s+|\s+)([a-z\s]+?)(?:\s|$|\.)/i;
        let match = text.match(cityCountryRegex);
        if (match) {
            const city = match[1].trim();
            const country = match[2].trim();
            if (!/\d{4}-\d{2}-\d{2}/.test(country) && !['from', 'to', 'on', 'at'].includes(country.toLowerCase())) {
                return { city, country };
            }
        }
        const cityRegex = /(?:hotel\s+in|stay\s+in|room\s+in|at|in)\s+([a-z\s]+?)(?:\s|$|\.)/i;
        match = text.match(cityRegex);
        if (match)
            return { city: match[1].trim(), country: null };
        const cleaned = text.trim();
        const skipKeywords = ['flight', 'hotel', 'cancel', 'booking', 'help'];
        if (cleaned.length > 1 &&
            /^[a-zA-Z\s]+$/.test(cleaned) &&
            !skipKeywords.some((kw) => cleaned.toLowerCase().includes(kw))) {
            return { city: cleaned, country: null };
        }
        return { city: null, country: null };
    }
    validateFlightData(data) {
        if (!data.from)
            return 'I need a departure location. Where are you flying from?';
        if (!data.to)
            return 'Where would you like to fly to?';
        if (!data.departureDate)
            return 'What date would you like to depart? (format: YYYY-MM-DD)';
        return null;
    }
    validateHotelData(data) {
        if (!data.city)
            return 'Which city would you like to stay in?';
        if (!data.checkIn)
            return 'When is your check-in date? (format: YYYY-MM-DD)';
        if (!data.checkOut)
            return 'When is your check-out date? (format: YYYY-MM-DD)';
        return null;
    }
    clearFlightFields(sess) {
        sess.from = undefined;
        sess.to = undefined;
        sess.departureDate = undefined;
        sess.returnDate = undefined;
        sess.lastResults = undefined;
        sess.choice = undefined;
    }
    clearHotelFields(sess) {
        sess.city = undefined;
        sess.country = undefined;
        sess.checkIn = undefined;
        sess.checkOut = undefined;
        sess.adults = undefined;
        sess.children = undefined;
        sess.lastResults = undefined;
        sess.choice = undefined;
    }
    setBookingType(sess, type) {
        if (sess.bookingType !== type) {
            sess.bookingType = type;
            sess.state = 'idle';
            if (type === 'flight') {
                this.clearHotelFields(sess);
            }
            else {
                this.clearFlightFields(sess);
            }
        }
    }
    isBookingInfoRequest(text) {
        return /\b(?:booking|reservation)\s*(?:info|information|details?|status)\b/i.test(text) ||
            /\b(?:show|get|find|fetch|view|tell\s+me|what(?:'s| is)|give\s+me)\b.*\b(?:booking|reservation)\b/i.test(text);
    }
    isCancelBookingRequest(text) {
        return /\b(?:cancel|void|delete|remove)\b.*\b(?:booking|reservation)\b/i.test(text) ||
            /\bcancel\s+(?:my\s+)?(?:booking|reservation)\b/i.test(text);
    }
    extractBookingId(text, sess) {
        const explicitIdMatch = text.match(/\b(b_\d+)\b/i) || text.match(/\bbooking\s*(?:id|#|number)?\s*[:\-]?\s*(b_\d+)\b/i);
        if (explicitIdMatch?.[1]) {
            return explicitIdMatch[1];
        }
        if (sess?.lastBookingId && /\b(?:it|this|that|the\s+booking|my\s+booking)\b/i.test(text)) {
            return sess.lastBookingId;
        }
        return null;
    }
    async handleMessage(sessionId, message) {
        const sess = this.sessions.get(sessionId);
        const text = (message || '').toLowerCase().trim();
        const originalMessage = message.trim();
        if (/\b(?:hi|hello|help)\b/i.test(text)) {
            return {
                reply: "Hi! 👋 I can help you book flights or hotels. Try:\n• 'Book a flight from Mumbai to NYC'\n• 'Book a hotel in London'\n\nJust tell me what you need!",
            };
        }
        if (this.isBookingInfoRequest(originalMessage) || this.isCancelBookingRequest(originalMessage)) {
            const bookingId = this.extractBookingId(originalMessage, sess);
            if (this.isBookingInfoRequest(originalMessage)) {
                if (!bookingId) {
                    return { reply: 'Please provide a booking ID for lookup.' };
                }
                sess.lastBookingId = bookingId;
                sess.lastBookingIntent = 'info';
                try {
                    const resp = await this.bookingsService.getBookingInfo(bookingId);
                    const body = resp?.body ?? resp;
                    if (body?.success === false && body?.message) {
                        return { reply: `I could not fetch booking info for ${bookingId}: ${body.message}` };
                    }
                    return { reply: `Booking info for ${bookingId}: ${JSON.stringify(body, null, 2)}` };
                }
                catch (err) {
                    return { reply: `Could not fetch booking info for ${bookingId}.` };
                }
            }
            if (this.isCancelBookingRequest(originalMessage)) {
                if (!bookingId) {
                    return { reply: 'Please provide a booking ID to cancel.' };
                }
                sess.lastBookingId = bookingId;
                sess.lastBookingIntent = 'cancel';
                try {
                    const resp = await this.bookingsService.cancelBooking(bookingId);
                    const body = resp?.body ?? resp;
                    if (body?.success === false && body?.message) {
                        return { reply: `I could not cancel booking ${bookingId}: ${body.message}` };
                    }
                    return { reply: `Cancellation response for ${bookingId}: ${JSON.stringify(body, null, 2)}` };
                }
                catch (err) {
                    console.error('Cancel booking error', err);
                    return { reply: `Could not cancel booking ${bookingId}.` };
                }
            }
        }
        if (sess.bookingType === 'hotel') {
            if (sess.state === 'awaiting_city' && originalMessage) {
                sess.city = originalMessage.trim();
                sess.state = 'awaiting_checkin';
                return { reply: 'Great, got the city. What is your check-in date? (YYYY-MM-DD)' };
            }
            if (sess.state === 'awaiting_checkin' && originalMessage) {
                sess.checkIn = originalMessage.trim();
                sess.state = 'awaiting_checkout';
                return { reply: 'Thanks. What is your check-out date? (YYYY-MM-DD)' };
            }
            if (sess.state === 'awaiting_checkout' && originalMessage) {
                sess.checkOut = originalMessage.trim();
                sess.state = 'hotel_ready';
            }
        }
        if (/\b(?:book\s+flight|switch\s+to\s+flight|flight|fly|departure)\b/i.test(originalMessage)) {
            this.setBookingType(sess, 'flight');
            const parsedRoute = this.extractLocations(originalMessage);
            if (!parsedRoute.from && !parsedRoute.to && !this.extractDates(originalMessage).length) {
                return { reply: 'Sure, let’s book a flight. Where are you flying from and to (YYYY-MM-DD)?' };
            }
        }
        if (/\b(?:book\s+hotel|switch\s+to\s+hotel|hotel|stay|room|accommodation)\b/i.test(originalMessage)) {
            this.setBookingType(sess, 'hotel');
            if (text.includes('in') && this.extractCity(originalMessage)) {
            }
            else {
                return { reply: 'Sure, let’s book a hotel. Which city do you want to stay in?' };
            }
        }
        if (text.includes('revalidate hotel') || text.includes('revalidate')) {
            if (!sess.choice || !sess.choice.hotelId) {
                return { reply: 'No hotel selected yet to revalidate. Please choose a hotel first.' };
            }
            const token = sess.choice.token || '';
            const recommendationId = sess.choice.recommendationId || '';
            try {
                const resp = await this.bookingsService.revalidateHotel(token, recommendationId, sess.choice.hotelId);
                return { reply: `Hotel revalidate response: ${JSON.stringify(resp, null, 2)}` };
            }
            catch (err) {
                console.error('Hotel revalidation error', err);
                return { reply: 'Could not revalidate hotel right now.' };
            }
        }
        if (sess.state === 'completed') {
            const noPattern = /\b(no|nope|nah|not now|not anymore|stop|thanks?)\b/i;
            const yesPattern = /\b(yes|yeah|yep|sure|okay|ok)\b/i;
            if (noPattern.test(originalMessage)) {
                this.sessions.set(sessionId, { state: 'idle', bookingType: undefined });
                return { reply: 'Thank you! If you need more help later, I am here for you. Have a great day!' };
            }
            if (yesPattern.test(originalMessage)) {
                this.sessions.set(sessionId, { state: 'idle', bookingType: undefined });
                return { reply: 'Great! Would you like to book a flight or a hotel?' };
            }
            return { reply: 'Would you like to book another flight or hotel? (yes/no)' };
        }
        if (!sess.bookingType) {
            if (text.includes('flight') || text.includes('fly') || text.includes('departure')) {
                sess.bookingType = 'flight';
            }
            else if (text.includes('hotel') ||
                text.includes('stay') ||
                text.includes('room') ||
                text.includes('accommodation')) {
                sess.bookingType = 'hotel';
            }
            else {
                return {
                    reply: "Are you looking to book a flight or a hotel?",
                };
            }
        }
        const selectionText = text;
        if (selectionText.startsWith('select:') || /^(?:select|choose|pick|#|number)\s*\d+/i.test(selectionText)) {
            let raw;
            if (selectionText.startsWith('select:')) {
                raw = originalMessage.replace(/^select:/i, '').trim();
            }
            else {
                raw = selectionText.match(/^(?:select|choose|pick|#|number)\s*(\d+)/i)?.[1];
            }
            if (!raw) {
                return { reply: 'Please pick a valid option number or select:ID.' };
            }
            let itemId = raw.trim();
            let key0;
            if (itemId.includes('|')) {
                const parts = itemId.split('|');
                itemId = parts[0].trim();
                const maybe = Number(parts[1]);
                if (!Number.isNaN(maybe))
                    key0 = maybe;
            }
            let selected = sess.lastResults?.find((item) => {
                if (!item)
                    return false;
                const candidateIds = [item.fareSourceCode, item.id, item?.id && `flight_${item.id}`]
                    .filter(Boolean)
                    .map((x) => String(x).trim());
                return candidateIds.some((cid) => cid === itemId || cid.toLowerCase() === itemId.toLowerCase());
            });
            if (!selected && /^[0-9]+$/.test(itemId) && sess.lastResults?.length) {
                const idx = Number(itemId) - 1;
                if (idx >= 0 && idx < sess.lastResults.length) {
                    selected = sess.lastResults[idx];
                }
            }
            if (!selected) {
                return { reply: "I couldn't find that option. Please select from the list above." };
            }
            if (sess.bookingType === 'flight') {
                const fareSourceCode = selected?.fareSourceCode || selected?.id || itemId;
                const computedKey0 = key0 ?? Number(selected?.key_0 ?? selected?.coin ?? selected?.showOurprice ?? selected?.totalFare ?? 0);
                if (!fareSourceCode) {
                    return { reply: 'Unable to determine fare source for selected flight; please try again.' };
                }
                if (!computedKey0 || Number.isNaN(computedKey0)) {
                    return { reply: 'Unable to determine flight key (key_0) value. Please select again from the list.' };
                }
                try {
                    const revalidate = await this.bookingsService.revalidateFlight(fareSourceCode, computedKey0);
                    if (!revalidate?.success) {
                        return { reply: `Sorry, flight revalidation failed: ${revalidate?.message ?? 'Unknown error'}.` };
                    }
                    sess.choice = { ...selected, revalidate: revalidate.result };
                    sess.state = 'awaiting_name';
                    return {
                        reply: `Excellent choice! Fare revalidated to ${revalidate.result?.pricing?.showOurprice ?? revalidate.result?.pricing?.ourprice}. Who should I book this for? (full name)`,
                    };
                }
                catch (error) {
                    console.error('Flight revalidation error:', error);
                    return { reply: 'Could not revalidate your selected flight right now. Please try again.' };
                }
            }
            if (sess.bookingType === 'hotel') {
                try {
                    const detailsResp = await this.bookingsService.getHotelDetails(selected.id || selected.hotelId || '');
                    const details = detailsResp?.body ?? detailsResp;
                    const token = selected.token || details?.token || details?.result?.token || '';
                    const roomRatesResp = token
                        ? await this.bookingsService.getRoomsAndRates(token, selected.id || selected.hotelId || '')
                        : null;
                    const roomRates = roomRatesResp?.body ?? roomRatesResp;
                    sess.choice = {
                        ...selected,
                        details,
                        roomRates,
                    };
                    sess.state = 'awaiting_name';
                    return {
                        reply: `Excellent choice! ${selected?.name ?? 'Selected hotel'} has been locked. ` +
                            `Hotel info loaded. Please provide guest full name to complete booking.`,
                    };
                }
                catch (error) {
                    console.error('Hotel details/rates error:', error);
                    sess.choice = selected;
                    sess.state = 'awaiting_name';
                    return {
                        reply: `Selected ${selected?.name ?? 'hotel'}. Unable to pre-fetch details now, but we can continue. Who should I book this for? (full name)`,
                    };
                }
            }
            sess.choice = selected;
            sess.state = 'awaiting_name';
            return {
                reply: `Excellent choice! ${selected?.name ?? 'Selected item'} is a great option. Who should I book this for? (full name)`,
            };
        }
        if (sess.state === 'awaiting_name' && originalMessage.length > 2) {
            if (!sess.choice) {
                return { reply: 'Please select an option first.' };
            }
            const name = originalMessage.trim();
            sess.state = 'booking';
            try {
                const booking = this.bookingsService.createBooking({
                    name,
                    type: sess.bookingType,
                    itemId: sess.choice.fareSourceCode || sess.choice.id || 'unknown',
                    details: sess.bookingType === 'flight'
                        ? `From: ${sess.from}, To: ${sess.to}, Date: ${sess.departureDate}`
                        : `City: ${sess.city}, CheckIn: ${sess.checkIn}, CheckOut: ${sess.checkOut}`,
                });
                sess.state = 'completed';
                return {
                    reply: `🎉 Your booking is confirmed! Booking ID: ${booking.id}\nPassenger/Guest: ${name}\n\nWould you like to make another booking?`,
                    booking,
                };
            }
            catch (error) {
                console.error('Booking creation error:', error);
                sess.state = 'error';
                return {
                    reply: 'Sorry, there was an error creating your booking. Please try again.',
                };
            }
        }
        if (sess.bookingType === 'flight') {
            const { from, to } = this.extractLocations(originalMessage);
            console.log(`[Flight Booking] Extracted locations: from="${from}", to="${to}"`);
            if (from)
                sess.from = from;
            if (to)
                sess.to = to;
            if (!from && !to) {
                const trimmed = originalMessage.trim();
                if (/^[a-zA-Z\s]+$/.test(trimmed) &&
                    trimmed.length > 1 &&
                    !/\b(?:book|flight|fly|departure|adults?|children?|date|from|to|on|for|with)\b/i.test(trimmed)) {
                    if (!sess.from) {
                        sess.from = trimmed;
                    }
                    else if (!sess.to) {
                        sess.to = trimmed;
                    }
                }
            }
            const dates = this.extractDates(originalMessage);
            console.log(`[Flight Booking] Extracted dates:`, dates);
            if (dates.length > 0)
                sess.departureDate = dates[0];
            if (dates.length > 1)
                sess.returnDate = dates[1];
            console.log(`[Flight Booking] Session data before validation:`, {
                from: sess.from,
                to: sess.to,
                departureDate: sess.departureDate,
            });
            const validationError = this.validateFlightData(sess);
            if (validationError) {
                console.log(`[Flight Booking] Validation error: ${validationError}`);
                return { reply: validationError };
            }
            sess.state = 'searching_flights';
            console.log(`[Flight Booking] All data present. Searching flights with:`, {
                from: sess.from,
                to: sess.to,
                departureDate: sess.departureDate,
            });
            try {
                const flightResponse = await this.bookingsService.findFlights(sess.from, sess.to, sess.departureDate);
                const flightItems = (flightResponse && Array.isArray(flightResponse.result))
                    ? flightResponse.result
                    : [];
                sess.lastResults = flightItems;
                sess.state = 'choosing_flight';
                return {
                    reply: `Great! I found flights from ${sess.from?.toUpperCase()} to ${sess.to?.toUpperCase()} on ${sess.departureDate}. Which one would you like?`,
                    cards: flightResponse,
                };
            }
            catch (error) {
                sess.state = 'error';
                console.error('Flight search error:', error);
                return {
                    reply: `Sorry, I couldn't find flights from ${sess.from} to ${sess.to}. Please try again or choose different cities.`,
                };
            }
        }
        if (sess.bookingType === 'hotel') {
            const { city: cityFromMessage, country: countryFromMessage } = this.extractCity(originalMessage);
            if (cityFromMessage)
                sess.city = cityFromMessage;
            if (countryFromMessage)
                sess.country = countryFromMessage;
            const dates = this.extractDates(originalMessage);
            if (dates.length > 1) {
                sess.checkIn = dates[0];
                sess.checkOut = dates[1];
            }
            else if (dates.length == 1) {
                if (!sess.checkIn) {
                    sess.checkIn = dates[0];
                }
                else if (!sess.checkOut) {
                    sess.checkOut = dates[0];
                }
            }
            if (!sess.city) {
                sess.state = 'awaiting_city';
                return { reply: 'Which city would you like to book a hotel in?' };
            }
            if (!sess.checkIn) {
                sess.state = 'awaiting_checkin';
                return { reply: 'Please provide the check-in date (YYYY-MM-DD).' };
            }
            if (!sess.checkOut) {
                sess.state = 'awaiting_checkout';
                return { reply: 'Please provide the check-out date (YYYY-MM-DD).' };
            }
            sess.state = 'searching_hotels';
            try {
                const searchCity = sess.country ? `${sess.city}, ${sess.country}` : sess.city;
                const destRes = await this.bookingsService.searchDestinations(searchCity);
                const destData = destRes?.body ?? destRes;
                const destinations = destData?.result ?? [];
                if (!Array.isArray(destinations) || destinations.length === 0) {
                    return {
                        reply: `Could not find destination info for ${searchCity}. Please try a different city.`,
                    };
                }
                const hotels = await this.bookingsService.findHotels(searchCity, sess.checkIn, sess.checkOut);
                const hotelsBody = hotels?.body ?? hotels;
                if (hotelsBody?.success === false && hotelsBody?.code === 204) {
                    return {
                        reply: `No hotels available in ${sess.city} from ${sess.checkIn} to ${sess.checkOut}. ` +
                            `Try different dates or a nearby city.`,
                    };
                }
                const hotelItems = (hotelsBody?.result?.result && Array.isArray(hotelsBody.result.result))
                    ? hotelsBody.result.result
                    : Array.isArray(hotelsBody?.result)
                        ? hotelsBody.result
                        : Array.isArray(hotelsBody)
                            ? hotelsBody
                            : [];
                if (!hotelItems.length) {
                    return {
                        reply: `No hotels found in ${sess.city} for ${sess.checkIn} to ${sess.checkOut}. Please try different dates or a nearby city.`,
                    };
                }
                sess.lastResults = hotelItems;
                sess.state = 'choosing_hotel';
                const formattedCards = hotelItems.map((hotel, index) => ({
                    id: hotel.id,
                    name: hotel.name,
                    providerName: hotel.providerName || 'EAN',
                    starRating: hotel.starRating,
                    ourprice: hotel.ourprice,
                    baseprice: hotel.baseprice || 0,
                    saving: hotel.saving || 0,
                    distance: hotel.distance,
                    heroImage: hotel.heroImage,
                    contact: hotel.contact,
                    reviews: hotel.reviews,
                    mainamenity: hotel.mainamenity,
                    facilities: hotel.facilities?.slice(0, 5) || [],
                    token: hotel.token,
                }));
                return {
                    sessionId,
                    reply: `Perfect! I found hotels in ${searchCity} from ${sess.checkIn} to ${sess.checkOut}. Which one interests you?`,
                    cards: formattedCards,
                };
            }
            catch (error) {
                sess.state = 'error';
                console.error('Hotel search error:', error);
                return {
                    reply: `Sorry, I couldn't find hotels in ${sess.city} for those dates. Please try different dates or cities.`,
                };
            }
        }
        if (text.startsWith('select:')) {
            const itemId = text.replace('select:', '').trim();
            const selected = sess.lastResults?.find((item) => item?.fareSourceCode === itemId || item?.id === itemId);
            if (selected) {
                if (sess.bookingType === 'flight') {
                    const fareSourceCode = selected.fareSourceCode || selected.id;
                    const key0 = Number(selected.coin ?? selected.showOurprice ?? selected.totalFare ?? 0);
                    try {
                        const revalidate = await this.bookingsService.revalidateFlight(fareSourceCode, key0);
                        if (!revalidate?.success) {
                            return { reply: `Sorry, flight revalidation failed: ${revalidate?.message ?? 'Unknown error'}.` };
                        }
                        sess.choice = { ...selected, revalidate: revalidate.result };
                        sess.state = 'awaiting_name';
                        return {
                            reply: `Excellent choice! Flight fare is valid. Final price is ${revalidate.result?.pricing?.showOurprice ?? revalidate.result?.pricing?.ourprice}. Who should I book this for (full name)?`,
                        };
                    }
                    catch (error) {
                        console.error('Flight revalidation error:', error);
                        return { reply: 'Could not revalidate your selected flight right now. Please try again.' };
                    }
                }
                sess.choice = selected;
                sess.state = 'awaiting_name';
                return {
                    reply: `Excellent choice! ${selected?.name ?? 'Selected item'} is a great option. Now, who should I book this for? (Please provide your full name)`,
                };
            }
            return { reply: "I couldn't find that option. Please select from the list above." };
        }
        const selectMatch = text.match(/^(?:select|choose|pick|#|number)\s*(\d+)/i);
        if (selectMatch && sess.lastResults?.length) {
            const idx = parseInt(selectMatch[1], 10) - 1;
            const selected = sess.lastResults[idx];
            if (selected && idx >= 0) {
                sess.choice = selected;
                sess.state = 'awaiting_name';
                return {
                    reply: `Perfect! You selected ${selected.name}. Who should I book this for? (Your full name)`,
                };
            }
            return { reply: `Please select a number between 1 and ${sess.lastResults.length}.` };
        }
        if (sess.state === 'completed') {
            if (text === 'no' || text === 'nope' || text === 'nah' || text === 'not now') {
                this.sessions.set(sessionId, {
                    state: 'idle',
                    bookingType: undefined,
                });
                return {
                    reply: 'Thank you! If you need more help later, I am here for you. Have a great day!',
                };
            }
            if ((text.includes('another') &&
                (text.includes('booking') || text.includes('search') || text.includes('again'))) ||
                text === 'yes') {
                this.sessions.set(sessionId, {
                    state: 'idle',
                    bookingType: undefined,
                });
                return {
                    reply: 'Great! Would you like to book a flight or a hotel?',
                };
            }
        }
        if ((text.includes('another') &&
            (text.includes('booking') || text.includes('search') || text.includes('again'))) ||
            text === 'yes') {
            this.sessions.set(sessionId, {
                state: 'idle',
                bookingType: undefined,
            });
            return {
                reply: 'Great! Would you like to book a flight or a hotel?',
            };
        }
        return {
            reply: `I'm here to help! What would you like to do:\n• Book a flight\n• Book a hotel\n\nJust tell me the details!`,
        };
    }
};
exports.ChatService = ChatService;
exports.ChatService = ChatService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [bookings_service_1.BookingsService])
], ChatService);
//# sourceMappingURL=chat.service.js.map