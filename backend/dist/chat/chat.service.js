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
                history: [],
            });
        }
        return id;
    }
    getOrCreateSession(sessionId) {
        const existing = this.sessions.get(sessionId);
        if (existing)
            return existing;
        const created = {
            state: 'idle',
            bookingType: undefined,
            history: [],
        };
        this.sessions.set(sessionId, created);
        return created;
    }
    addConversationTurn(sess, role, text) {
        const trimmed = (text || '').trim();
        if (!trimmed)
            return;
        if (!sess.history)
            sess.history = [];
        sess.history.push({ role, text: trimmed });
        if (sess.history.length > 12) {
            sess.history = sess.history.slice(-12);
        }
    }
    recordAssistantReply(sessionId, reply) {
        if (!reply)
            return;
        const sess = this.getOrCreateSession(sessionId);
        this.addConversationTurn(sess, 'assistant', reply);
    }
    getCompactHistory(sess, turns = 6) {
        if (!sess.history?.length)
            return [];
        return sess.history
            .slice(-turns)
            .map((h) => ({ role: h.role, text: h.text.slice(0, 180) }));
    }
    normalizeIsoDate(value) {
        if (!value)
            return undefined;
        const normalized = String(value).trim();
        const match = normalized.match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (!match)
            return undefined;
        const year = Number(match[1]);
        const month = Number(match[2]);
        const day = Number(match[3]);
        const parsed = new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00`);
        if (!Number.isFinite(parsed.getTime()))
            return undefined;
        if (parsed.getFullYear() !== year || parsed.getMonth() + 1 !== month || parsed.getDate() !== day) {
            return undefined;
        }
        return `${match[1]}-${match[2]}-${match[3]}`;
    }
    sanitizeLlmTextValue(value) {
        if (!value)
            return undefined;
        const cleaned = this.sanitizeLocationCandidate(String(value).trim());
        if (!cleaned)
            return undefined;
        if (!/^[a-zA-Z][a-zA-Z\s.'-]{1,49}$/.test(cleaned))
            return undefined;
        return cleaned;
    }
    sanitizeLlmInterpretation(raw) {
        if (!raw || typeof raw !== 'object')
            return null;
        const clean = {};
        if (raw.bookingType === 'flight' || raw.bookingType === 'hotel') {
            clean.bookingType = raw.bookingType;
        }
        const from = this.sanitizeLlmTextValue(raw.from ?? undefined);
        const to = this.sanitizeLlmTextValue(raw.to ?? undefined);
        const city = this.sanitizeLlmTextValue(raw.city ?? undefined);
        const country = this.sanitizeLlmTextValue(raw.country ?? undefined);
        if (from)
            clean.from = from;
        if (to)
            clean.to = to;
        if (city)
            clean.city = city;
        if (country)
            clean.country = country;
        const departureDate = this.normalizeIsoDate(raw.departureDate ?? undefined);
        if (departureDate && !this.isPastIsoDate(departureDate)) {
            clean.departureDate = departureDate;
        }
        const checkIn = this.normalizeIsoDate(raw.checkIn ?? undefined);
        if (checkIn && !this.isPastIsoDate(checkIn)) {
            clean.checkIn = checkIn;
        }
        const checkOut = this.normalizeIsoDate(raw.checkOut ?? undefined);
        if (checkOut && (!clean.checkIn || checkOut >= clean.checkIn)) {
            clean.checkOut = checkOut;
        }
        const bookingId = (raw.bookingId || '').trim();
        if (/^[a-zA-Z0-9_-]{3,40}$/.test(bookingId)) {
            clean.bookingId = bookingId;
        }
        if (Number.isInteger(raw.adults) && raw.adults >= 1 && raw.adults <= 9) {
            clean.adults = raw.adults;
        }
        if (Number.isInteger(raw.children) && raw.children >= 0 && raw.children <= 9) {
            clean.children = raw.children;
        }
        const allowedIntents = new Set([
            'flight booking',
            'hotel booking',
            'booking info',
            'booking cancellation',
            'selection',
            'unknown',
        ]);
        if (typeof raw.intent === 'string' && allowedIntents.has(raw.intent.trim().toLowerCase())) {
            clean.intent = raw.intent.trim().toLowerCase();
        }
        if (typeof raw.confidence === 'number' && raw.confidence >= 0 && raw.confidence <= 1) {
            clean.confidence = raw.confidence;
        }
        if (typeof raw.reply === 'string') {
            const reply = raw.reply.trim();
            if (reply && reply.length <= 300) {
                clean.reply = reply;
            }
        }
        return Object.keys(clean).length ? clean : null;
    }
    mergeLlmInterpretation(sess, interpretation) {
        if (interpretation.bookingType) {
            this.setBookingType(sess, interpretation.bookingType);
        }
        if (!sess.from && interpretation.from)
            sess.from = interpretation.from;
        if (!sess.to && interpretation.to)
            sess.to = interpretation.to;
        if (!sess.city && interpretation.city)
            sess.city = interpretation.city;
        if (!sess.country && interpretation.country)
            sess.country = interpretation.country;
        if (!sess.departureDate && interpretation.departureDate) {
            sess.departureDate = interpretation.departureDate;
        }
        if (!sess.checkIn && interpretation.checkIn)
            sess.checkIn = interpretation.checkIn;
        if (!sess.checkOut && interpretation.checkOut)
            sess.checkOut = interpretation.checkOut;
        if (sess.adults == null && interpretation.adults != null)
            sess.adults = interpretation.adults;
        if (sess.children == null && interpretation.children != null)
            sess.children = interpretation.children;
        if (interpretation.bookingId)
            sess.lastBookingId = interpretation.bookingId;
    }
    parseLlmJson(content) {
        const trimmed = content.trim();
        const jsonText = trimmed.startsWith('```')
            ? trimmed.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim()
            : trimmed;
        try {
            return JSON.parse(jsonText);
        }
        catch {
            const firstBrace = jsonText.indexOf('{');
            const lastBrace = jsonText.lastIndexOf('}');
            if (firstBrace >= 0 && lastBrace > firstBrace) {
                try {
                    return JSON.parse(jsonText.slice(firstBrace, lastBrace + 1));
                }
                catch {
                    return null;
                }
            }
            return null;
        }
    }
    async inferBookingContextWithLlm(message, sess) {
        const provider = (process.env.LLM_PROVIDER || process.env.LLM_PROVIDER_NAME || 'groq').toLowerCase();
        const apiKey = process.env.LLM_API_KEY ||
            process.env.GROQ_API_KEY ||
            process.env.OPENAI_API_KEY;
        if (!apiKey)
            return null;
        const baseUrl = (process.env.LLM_BASE_URL ||
            (provider === 'groq'
                ? process.env.GROQ_BASE_URL
                : process.env.OPENAI_BASE_URL) ||
            'https://api.groq.com/openai/v1')
            .replace(/\/$/, '');
        const model = process.env.LLM_MODEL ||
            (provider === 'groq'
                ? process.env.GROQ_MODEL
                : process.env.OPENAI_MODEL) ||
            'llama-3.1-8b-instant';
        const fetchFn = globalThis.fetch;
        if (typeof fetchFn !== 'function')
            return null;
        const payload = {
            session: {
                bookingType: sess.bookingType ?? null,
                from: sess.from ?? null,
                to: sess.to ?? null,
                city: sess.city ?? null,
                country: sess.country ?? null,
                departureDate: sess.departureDate ?? null,
                checkIn: sess.checkIn ?? null,
                checkOut: sess.checkOut ?? null,
                adults: sess.adults ?? null,
                children: sess.children ?? null,
            },
            history: this.getCompactHistory(sess, 6),
            message,
        };
        const systemPrompt = [
            'You are a travel booking assistant that extracts intent and missing slots.',
            'Return JSON only. Do not wrap the response in markdown.',
            'Supported intents: flight booking, hotel booking, booking info, booking cancellation, selection, unknown.',
            'Only fill values that are explicitly present in the user message or obvious from session context.',
            'Use null for any unknown field. Do not invent dates, cities, or booking IDs.',
            'Prefer ISO dates in YYYY-MM-DD when a date is clearly stated.',
            'Schema: {"bookingType":"flight|hotel|null","from":string|null,"to":string|null,"city":string|null,"country":string|null,"departureDate":string|null,"checkIn":string|null,"checkOut":string|null,"bookingId":string|null,"adults":number|null,"children":number|null,"intent":string|null,"confidence":number|null,"reply":string|null}'
        ].join(' ');
        try {
            const response = await fetchFn(`${baseUrl}/chat/completions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    Authorization: `Bearer ${apiKey}`,
                },
                body: JSON.stringify({
                    model,
                    temperature: 0,
                    response_format: { type: 'json_object' },
                    messages: [
                        { role: 'system', content: systemPrompt },
                        { role: 'user', content: JSON.stringify(payload) },
                    ],
                }),
            });
            if (!response.ok) {
                console.warn(`[LLM] inference request failed: ${response.status}`);
                return null;
            }
            const data = await response.json();
            const content = data?.choices?.[0]?.message?.content;
            if (typeof content !== 'string' || !content.trim())
                return null;
            const interpretation = this.sanitizeLlmInterpretation(this.parseLlmJson(content));
            if (!interpretation)
                return null;
            console.log('[LLM] sanitized interpretation:', JSON.stringify(interpretation));
            return interpretation;
        }
        catch (error) {
            console.warn('[LLM] inference failed:', error);
            return null;
        }
    }
    extractDates(text) {
        const dates = [];
        const seen = new Set();
        const pushDate = (value) => {
            if (!value)
                return;
            const normalized = this.normalizeIsoDate(value);
            if (!normalized || seen.has(normalized))
                return;
            seen.add(normalized);
            dates.push(normalized);
        };
        const isoRegex = /\b\d{4}-\d{2}-\d{2}\b/g;
        for (const match of text.matchAll(isoRegex)) {
            pushDate(match[0]);
        }
        const slashRegex = /\b(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})\b/g;
        for (const match of text.matchAll(slashRegex)) {
            const parsed = this.parseSlashDateMatch(match[1], match[2], match[3]);
            pushDate(parsed);
        }
        const monthFirstRegex = /\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|sept|october|oct|november|nov|december|dec)\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*(\d{4}))?\b/gi;
        for (const match of text.matchAll(monthFirstRegex)) {
            const parsed = this.parseMonthNameDate(match[1], match[2], match[3]);
            pushDate(parsed);
        }
        const dayFirstRegex = /\b(\d{1,2})(?:st|nd|rd|th)?\s+(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|sept|october|oct|november|nov|december|dec)(?:\s*,?\s*(\d{4}))?\b/gi;
        for (const match of text.matchAll(dayFirstRegex)) {
            const parsed = this.parseMonthNameDate(match[2], match[1], match[3]);
            pushDate(parsed);
        }
        if (!dates.length) {
            const relativeDate = this.extractRelativeDate(text);
            pushDate(relativeDate);
        }
        return dates;
    }
    isValidDateParts(year, month, day) {
        if (year < 1900 || year > 2100)
            return false;
        if (month < 1 || month > 12)
            return false;
        if (day < 1 || day > 31)
            return false;
        const date = new Date(year, month - 1, day);
        return (Number.isFinite(date.getTime()) &&
            date.getFullYear() === year &&
            date.getMonth() === month - 1 &&
            date.getDate() === day);
    }
    toIsoFromParts(year, month, day) {
        return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    }
    parseSlashDateMatch(firstRaw, secondRaw, yearRaw) {
        const first = Number(firstRaw);
        const second = Number(secondRaw);
        let year = Number(yearRaw);
        if (!Number.isFinite(first) || !Number.isFinite(second) || !Number.isFinite(year))
            return undefined;
        if (yearRaw.length === 2)
            year += 2000;
        const candidates = [];
        if (first > 12 && second <= 12) {
            candidates.push({ day: first, month: second });
        }
        else if (second > 12 && first <= 12) {
            candidates.push({ day: second, month: first });
        }
        else {
            candidates.push({ day: first, month: second });
            if (!(first === second)) {
                candidates.push({ day: second, month: first });
            }
        }
        for (const c of candidates) {
            if (this.isValidDateParts(year, c.month, c.day)) {
                return this.toIsoFromParts(year, c.month, c.day);
            }
        }
        return undefined;
    }
    parseMonthNameDate(monthText, dayText, yearText) {
        const monthMap = {
            january: 1,
            jan: 1,
            february: 2,
            feb: 2,
            march: 3,
            mar: 3,
            april: 4,
            apr: 4,
            may: 5,
            june: 6,
            jun: 6,
            july: 7,
            jul: 7,
            august: 8,
            aug: 8,
            september: 9,
            sep: 9,
            sept: 9,
            october: 10,
            oct: 10,
            november: 11,
            nov: 11,
            december: 12,
            dec: 12,
        };
        const month = monthMap[monthText.toLowerCase()];
        const day = Number(dayText);
        if (!month || !Number.isFinite(day))
            return undefined;
        let year = yearText ? Number(yearText) : new Date().getFullYear();
        if (!Number.isFinite(year))
            return undefined;
        if (!this.isValidDateParts(year, month, day))
            return undefined;
        let iso = this.toIsoFromParts(year, month, day);
        if (!yearText && this.isPastIsoDate(iso)) {
            year += 1;
            if (this.isValidDateParts(year, month, day)) {
                iso = this.toIsoFromParts(year, month, day);
            }
        }
        return iso;
    }
    toIsoDate(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }
    getNextWeekday(targetWeekday) {
        const now = new Date();
        const todayWeekday = now.getDay();
        let delta = (targetWeekday - todayWeekday + 7) % 7;
        if (delta === 0)
            delta = 7;
        const result = new Date(now);
        result.setDate(now.getDate() + delta);
        return result;
    }
    extractRelativeDate(text) {
        const lower = text.toLowerCase();
        const now = new Date();
        if (/\btoday\b/.test(lower)) {
            return this.toIsoDate(now);
        }
        if (/\btomorrow\b/.test(lower)) {
            const tomorrow = new Date(now);
            tomorrow.setDate(now.getDate() + 1);
            return this.toIsoDate(tomorrow);
        }
        if (/\bnext\s+week\b/.test(lower)) {
            const nextWeek = new Date(now);
            nextWeek.setDate(now.getDate() + 7);
            return this.toIsoDate(nextWeek);
        }
        const weekdays = {
            sunday: 0,
            monday: 1,
            tuesday: 2,
            wednesday: 3,
            thursday: 4,
            friday: 5,
            saturday: 6,
        };
        const nextWeekdayMatch = lower.match(/\bnext\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/);
        if (nextWeekdayMatch) {
            const weekday = weekdays[nextWeekdayMatch[1]];
            return this.toIsoDate(this.getNextWeekday(weekday));
        }
        return null;
    }
    sanitizeLocationCandidate(value) {
        if (!value)
            return value;
        const cleaned = value
            .replace(/\bnext\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/gi, ' ')
            .replace(/\bnext\s+week\b/gi, ' ')
            .replace(/\b(today|tomorrow|tonight|this\s+weekend)\b/gi, ' ')
            .replace(/\b(on|at)\s+\d{4}-\d{2}-\d{2}\b/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();
        return cleaned || undefined;
    }
    isPastIsoDate(dateText) {
        if (!dateText)
            return false;
        const normalized = String(dateText).trim();
        const isoMatch = normalized.match(/^(\d{4}-\d{2}-\d{2})/);
        if (!isoMatch)
            return false;
        const dateOnly = isoMatch[1];
        const today = new Date();
        const todayOnly = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        const parsed = new Date(`${dateOnly}T00:00:00`);
        return Number.isFinite(parsed.getTime()) && parsed < todayOnly;
    }
    hasPotentialDateMention(text) {
        return (/\b\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/.test(text) ||
            /\b\d{4}-\d{2}-\d{2}\b/.test(text) ||
            /\b(?:january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|sept|october|oct|november|nov|december|dec)\b/i.test(text) ||
            /\b(?:today|tomorrow|next\s+week|next\s+sunday|next\s+monday|next\s+tuesday|next\s+wednesday|next\s+thursday|next\s+friday|next\s+saturday)\b/i.test(text));
    }
    extractLocations(text) {
        const cleanedInput = text
            .replace(/\b(?:book|a|an|flight|flights|fly|please|search|find)\b/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();
        let fromToRegex = /(?:from|departure|origin|starting?\s+(?:from|at))\s+([a-z\s]+?)(?:\s+to\s+|\s+and\s+|\s*→\s*|\s*-\s*)([a-z\s]+?)(?:\s+on|\s+in|\s+for|\s+with|$|\.|,)/i;
        let match = cleanedInput.match(fromToRegex);
        if (match) {
            const from = this.sanitizeLocationCandidate(match[1].trim());
            const to = this.sanitizeLocationCandidate(match[2].trim());
            console.log('[extractLocations] Pattern 1 matched:', from, '→', to);
            return { from, to };
        }
        fromToRegex = /([a-z\s]+?)\s+to\s+([a-z\s]+?)(?:\s+on|\s+in|\s+for|\s+with|$|\.|,)/i;
        match = cleanedInput.match(fromToRegex);
        if (match) {
            const firstPart = match[1].toLowerCase();
            if (!['talk', 'speak', 'say', 'tell', 'listen'].includes(firstPart)) {
                const from = this.sanitizeLocationCandidate(match[1].trim());
                const to = this.sanitizeLocationCandidate(match[2].trim());
                console.log('[extractLocations] Pattern 2 matched:', from, '→', to);
                return { from, to };
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
        if (this.isPastIsoDate(data.departureDate)) {
            return 'Departure date cannot be in the past. Please provide a date that is today or later.';
        }
        return null;
    }
    validateHotelData(data) {
        if (!data.city)
            return 'Which city would you like to stay in?';
        if (!data.checkIn)
            return 'When is your check-in date? (format: YYYY-MM-DD)';
        if (!data.checkOut)
            return 'When is your check-out date? (format: YYYY-MM-DD)';
        if (this.isPastIsoDate(data.checkIn)) {
            return 'Check-in date cannot be in the past. Please provide a date that is today or later.';
        }
        if (this.isPastIsoDate(data.checkOut)) {
            return 'Check-out date cannot be in the past. Please provide a date that is today or later.';
        }
        if (data.checkOut < data.checkIn) {
            return `Check-out date (${data.checkOut}) cannot be before check-in date (${data.checkIn}). Please correct the dates.`;
        }
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
        const sess = this.getOrCreateSession(sessionId);
        const text = (message || '').toLowerCase().trim();
        const originalMessage = message.trim();
        this.addConversationTurn(sess, 'user', originalMessage);
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
                const parsedDates = this.extractDates(originalMessage);
                if (!parsedDates.length) {
                    return {
                        reply: 'That check-in date looks invalid. Please enter a valid date like YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, or April 2.',
                    };
                }
                if (this.isPastIsoDate(parsedDates[0])) {
                    return {
                        reply: 'Check-in date cannot be in the past. Please provide a future date.',
                    };
                }
                sess.checkIn = parsedDates[0];
                sess.state = 'awaiting_checkout';
                return { reply: 'Thanks. What is your check-out date? (YYYY-MM-DD)' };
            }
            if (sess.state === 'awaiting_checkout' && originalMessage) {
                const parsedDates = this.extractDates(originalMessage);
                if (!parsedDates.length) {
                    return {
                        reply: 'That check-out date looks invalid. Please enter a valid date like YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, or April 5.',
                    };
                }
                if (!sess.checkIn) {
                    sess.state = 'awaiting_checkin';
                    return { reply: 'Please provide the check-in date first.' };
                }
                if (parsedDates[0] < sess.checkIn) {
                    return {
                        reply: `Check-out date (${parsedDates[0]}) cannot be before check-in date (${sess.checkIn}). Please provide a valid check-out date.`,
                    };
                }
                sess.checkOut = parsedDates[0];
                sess.state = 'hotel_ready';
            }
        }
        const shouldUseLlmForIntent = !sess.bookingType &&
            !this.isBookingInfoRequest(originalMessage) &&
            !this.isCancelBookingRequest(originalMessage) &&
            !text.startsWith('select:') &&
            !/^(?:select|choose|pick|#|number)\s*\d+/i.test(text);
        if (shouldUseLlmForIntent) {
            const interpretation = await this.inferBookingContextWithLlm(originalMessage, sess);
            if (interpretation) {
                this.mergeLlmInterpretation(sess, interpretation);
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
            if (this.hasPotentialDateMention(originalMessage) && dates.length === 0) {
                return {
                    reply: 'I could not understand the travel date. Please provide it as YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, or month format like April 2.',
                };
            }
            if (dates.length > 0)
                sess.departureDate = dates[0];
            if (dates.length > 1)
                sess.returnDate = dates[1];
            if (sess.departureDate && this.isPastIsoDate(sess.departureDate)) {
                return {
                    reply: `Your departure date ${sess.departureDate} is in the past. Please provide a future departure date.`,
                };
            }
            if (this.isPastIsoDate(sess.departureDate)) {
                sess.departureDate = undefined;
            }
            if (sess.from && sess.to && sess.from.trim().toLowerCase() === sess.to.trim().toLowerCase()) {
                return {
                    reply: 'Origin and destination cannot be the same. Please provide different cities/airports.',
                };
            }
            if (!sess.from || !sess.to || !sess.departureDate) {
                const interpretation = await this.inferBookingContextWithLlm(originalMessage, sess);
                if (interpretation) {
                    this.mergeLlmInterpretation(sess, interpretation);
                }
            }
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
                if (error instanceof common_1.BadRequestException) {
                    return { reply: error.message };
                }
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
            if (this.hasPotentialDateMention(originalMessage) && dates.length === 0) {
                return {
                    reply: 'I could not understand your hotel dates. Please use YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, or month format like April 2 and April 5.',
                };
            }
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
            if (sess.checkIn && this.isPastIsoDate(sess.checkIn)) {
                return {
                    reply: `Check-in date ${sess.checkIn} is in the past. Please provide a future check-in date.`,
                };
            }
            if (sess.checkIn && sess.checkOut && sess.checkOut < sess.checkIn) {
                return {
                    reply: `Check-out date (${sess.checkOut}) cannot be before check-in date (${sess.checkIn}). Please correct the dates.`,
                };
            }
            if (!sess.city || !sess.checkIn || !sess.checkOut) {
                const interpretation = await this.inferBookingContextWithLlm(originalMessage, sess);
                if (interpretation) {
                    this.mergeLlmInterpretation(sess, interpretation);
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
                    correlationId: hotel.correlationId || hotel.result?.correlationId,
                }));
                return {
                    sessionId,
                    reply: `Perfect! I found hotels in ${searchCity} from ${sess.checkIn} to ${sess.checkOut}. Which one interests you?`,
                    checkIn: sess.checkIn,
                    checkOut: sess.checkOut,
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