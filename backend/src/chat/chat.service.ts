import { Injectable } from '@nestjs/common';
import { BookingsService } from '../bookings/bookings.service';

interface SessionData {
  state: string;
  bookingType?: 'flight' | 'hotel';
  from?: string;
  to?: string;
  city?: string;
  departureDate?: string;
  returnDate?: string;
  checkIn?: string;
  checkOut?: string;
  lastResults?: any[];
  choice?: any;
}

@Injectable()
export class ChatService {
  private sessions: Map<string, SessionData> = new Map();

  constructor(private readonly bookingsService: BookingsService) {}

  ensureSession(sessionId?: string): string {
    const id = sessionId || `s_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    if (!this.sessions.has(id)) {
      this.sessions.set(id, {
        state: 'idle',
        bookingType: undefined,
      });
    }
    return id;
  }

  private extractDates(text: string): string[] {
    const dateRegex = /\d{4}-\d{2}-\d{2}/g;
    return text.match(dateRegex) || [];
  }

  private extractLocations(text: string): { from?: string; to?: string } {
    // Try multiple patterns to capture locations
    
    // Pattern 1: "from X to Y" or "from X and Y"
    let fromToRegex = /(?:from|departure|origin|starting?\s+(?:from|at))\s+([a-z\s]+?)(?:\s+to\s+|\s+and\s+|\s*→\s*|\s*-\s*)([a-z\s]+?)(?:\s+on|\s+in|$|\.)/i;
    let match = text.match(fromToRegex);
    if (match) {
      console.log('[extractLocations] Pattern 1 matched:', match[1], '→', match[2]);
      return { from: match[1].trim(), to: match[2].trim() };
    }

    // Pattern 2: "X to Y" (simpler, no "from" keyword)
    fromToRegex = /([a-z\s]+?)\s+to\s+([a-z\s]+?)(?:\s+on|\s+in|$|\.)/i;
    match = text.match(fromToRegex);
    if (match) {
      // Make sure it's not matching something like "talk to"
      const firstPart = match[1].toLowerCase();
      if (!['talk', 'speak', 'say', 'tell', 'listen'].includes(firstPart)) {
        console.log('[extractLocations] Pattern 2 matched:', match[1], '→', match[2]);
        return { from: match[1].trim(), to: match[2].trim() };
      }
    }

    console.log('[extractLocations] No patterns matched. Input:', text);
    return {};
  }

  private extractCity(text: string): string | null {
    const cityRegex = /(?:hotel\s+in|stay\s+in|room\s+in|at|in)\s+([a-z\s]+?)(?:\s|$|\.)/i;
    const match = text.match(cityRegex);
    return match ? match[1].trim() : null;
  }

  private validateFlightData(data: SessionData): string | null {
    if (!data.from) return 'I need a departure location. Where are you flying from?';
    if (!data.to) return 'Where would you like to fly to?';
    if (!data.departureDate) return 'What date would you like to depart? (format: YYYY-MM-DD)';
    return null;
  }

  private validateHotelData(data: SessionData): string | null {
    if (!data.city) return 'Which city would you like to stay in?';
    if (!data.checkIn) return 'When is your check-in date? (format: YYYY-MM-DD)';
    if (!data.checkOut) return 'When is your check-out date? (format: YYYY-MM-DD)';
    return null;
  }

  async handleMessage(sessionId: string, message: string) {
    const sess = this.sessions.get(sessionId);
    const text = (message || '').toLowerCase().trim();
    const originalMessage = message.trim();

    // Handle greeting
    if (text.includes('hi') || text.includes('hello') || text.includes('help')) {
      return {
        reply: "Hi! 👋 I can help you book flights or hotels. Try:\n• 'Book a flight from Mumbai to NYC'\n• 'Book a hotel in London'\n\nJust tell me what you need!",
      };
    }

    // --- STEP 0: POST-BOOKING COMPLETION YES/NO ---
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

      // If user says something else in completed state, gently ask what they want next.
      return { reply: 'Would you like to book another flight or hotel? (yes/no)' };
    }

    // --- STEP 1: IDENTIFY BOOKING TYPE (if not set) ---
    if (!sess.bookingType) {
      if (text.includes('flight') || text.includes('fly') || text.includes('departure')) {
        sess.bookingType = 'flight';
      } else if (
        text.includes('hotel') ||
        text.includes('stay') ||
        text.includes('room') ||
        text.includes('accommodation')
      ) {
        sess.bookingType = 'hotel';
      } else {
        return {
          reply: "Are you looking to book a flight or a hotel?",
        };
      }
    }

    // --- SELECTION HANDLING (do this before any new search) ---
    const selectionText = text;
    if (selectionText.startsWith('select:') || /^(?:select|choose|pick|#|number)\s*\d+/i.test(selectionText)) {
      let raw: string | undefined;
      if (selectionText.startsWith('select:')) {
        raw = originalMessage.replace(/^select:/i, '').trim();
      } else {
        raw = selectionText.match(/^(?:select|choose|pick|#|number)\s*(\d+)/i)?.[1];
      }

      if (!raw) {
        return { reply: 'Please pick a valid option number or select:ID.' };
      }

      // allow format select:<id>|<key0>
      let itemId = raw.trim();
      let key0: number | undefined;
      if (itemId.includes('|')) {
        const parts = itemId.split('|');
        itemId = parts[0].trim();
        const maybe = Number(parts[1]);
        if (!Number.isNaN(maybe)) key0 = maybe;
      }

      let selected = sess.lastResults?.find((item) => {
        if (!item) return false;
        const candidateIds = [item.fareSourceCode, item.id, item?.id && `flight_${item.id}`]
          .filter(Boolean)
          .map((x) => String(x).trim());

        return candidateIds.some((cid) => cid === itemId || cid.toLowerCase() === itemId.toLowerCase());
      });

      // also support numeric option like "select 1" with indexing
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
        } catch (error) {
          console.error('Flight revalidation error:', error);
          return { reply: 'Could not revalidate your selected flight right now. Please try again.' };
        }
      }

      sess.choice = selected;
      sess.state = 'awaiting_name';
      return {
        reply: `Excellent choice! ${selected?.name ?? 'Selected item'} is a great option. Who should I book this for? (full name)`,
      };
    }

    // --- STEP 2a: FINALIZE BOOKING ON NAME ANSWER ---
    if (sess.state === 'awaiting_name' && originalMessage.length > 2) {
      if (!sess.choice) {
        return { reply: 'Please select an option first.' };
      }

      const name = originalMessage.trim();
      sess.state = 'booking';

      try {
        const booking = this.bookingsService.createBooking({
          name,
          type: sess.bookingType!,
          itemId: sess.choice.fareSourceCode || sess.choice.id || 'unknown',
          details:
            sess.bookingType === 'flight'
              ? `From: ${sess.from}, To: ${sess.to}, Date: ${sess.departureDate}`
              : `City: ${sess.city}, CheckIn: ${sess.checkIn}, CheckOut: ${sess.checkOut}`,
        } as any);

        sess.state = 'completed';
        return {
          reply: `🎉 Your booking is confirmed! Booking ID: ${booking.id}\nPassenger/Guest: ${name}\n\nWould you like to make another booking?`,
          booking,
        };
      } catch (error) {
        console.error('Booking creation error:', error);
        sess.state = 'error';
        return {
          reply: 'Sorry, there was an error creating your booking. Please try again.',
        };
      }
    }

    // --- STEP 2: COLLECT DATA FOR FLIGHTS ---
    if (sess.bookingType === 'flight') {
      // Extract locations
      const { from, to } = this.extractLocations(originalMessage);
      console.log(`[Flight Booking] Extracted locations: from="${from}", to="${to}"`);
      if (from) sess.from = from;
      if (to) sess.to = to;

      // Extract departure date
      const dates = this.extractDates(originalMessage);
      console.log(`[Flight Booking] Extracted dates:`, dates);
      if (dates.length > 0) sess.departureDate = dates[0];
      if (dates.length > 1) sess.returnDate = dates[1];

      // Log current session data
      console.log(`[Flight Booking] Session data before validation:`, {
        from: sess.from,
        to: sess.to,
        departureDate: sess.departureDate,
      });

      // Validate
      const validationError = this.validateFlightData(sess);
      if (validationError) {
        console.log(`[Flight Booking] Validation error: ${validationError}`);
        return { reply: validationError };
      }

      // All data collected - search flights
      sess.state = 'searching_flights';
      console.log(`[Flight Booking] All data present. Searching flights with:`, {
        from: sess.from,
        to: sess.to,
        departureDate: sess.departureDate,
      });
      try {
        const flightResponse = await this.bookingsService.findFlights(
          sess.from!,
          sess.to!,
          sess.departureDate!,
        );

        const flightItems = (flightResponse && Array.isArray((flightResponse as any).result))
          ? (flightResponse as any).result
          : [];

        // Keep raw results for selection, each result includes fareSourceCode, coin etc.
        sess.lastResults = flightItems;
        sess.state = 'choosing_flight';

        return {
          reply: `Great! I found flights from ${sess.from?.toUpperCase()} to ${sess.to?.toUpperCase()} on ${sess.departureDate}. Which one would you like?`,
          cards: flightResponse,
        };
      } catch (error) {
        sess.state = 'error';
        console.error('Flight search error:', error);
        return {
          reply: `Sorry, I couldn't find flights from ${sess.from} to ${sess.to}. Please try again or choose different cities.`,
        };
      }
    }

    // --- STEP 3: COLLECT DATA FOR HOTELS ---
    if (sess.bookingType === 'hotel') {
      // Extract city
      const cityFromMessage = this.extractCity(originalMessage);
      if (cityFromMessage) sess.city = cityFromMessage;

      // Extract dates
      const dates = this.extractDates(originalMessage);
      if (dates.length > 0) sess.checkIn = dates[0];
      if (dates.length > 1) sess.checkOut = dates[1];

      // Validate
      const validationError = this.validateHotelData(sess);
      if (validationError) {
        return { reply: validationError };
      }

      // All data collected - search hotels
      sess.state = 'searching_hotels';
      try {
        const hotels = await this.bookingsService.findHotels(
          sess.city!,
          sess.checkIn!,
          sess.checkOut!,
        );
        sess.lastResults = hotels;
        sess.state = 'choosing_hotel';

        return {
          reply: `Perfect! I found hotels in ${sess.city} from ${sess.checkIn} to ${sess.checkOut}. Which one interests you?`,
          cards: hotels,
        };
      } catch (error) {
        sess.state = 'error';
        console.error('Hotel search error:', error);
        return {
          reply: `Sorry, I couldn't find hotels in ${sess.city} for those dates. Please try different dates or cities.`,
        };
      }
    }

    // --- STEP 4: HANDLE SELECTION ---
    if (text.startsWith('select:')) {
      const itemId = text.replace('select:', '').trim();
      const selected = sess.lastResults?.find(
        (item) => item?.fareSourceCode === itemId || item?.id === itemId,
      );

      if (selected) {
        // Revalidate selected flight with the MCP endpoint
        if (sess.bookingType === 'flight') {
          const fareSourceCode = selected.fareSourceCode || selected.id;
          const key0 = Number(selected.coin ?? selected.showOurprice ?? selected.totalFare ?? 0);

          try {
            const revalidate = await this.bookingsService.revalidateFlight(fareSourceCode, key0);
            if (!revalidate?.success) {
              return { reply: `Sorry, flight revalidation failed: ${revalidate?.message ?? 'Unknown error'}.` };
            }

            // Store choice with revalidation result
            sess.choice = { ...selected, revalidate: revalidate.result };
            sess.state = 'awaiting_name';

            return {
              reply: `Excellent choice! Flight fare is valid. Final price is ${revalidate.result?.pricing?.showOurprice ?? revalidate.result?.pricing?.ourprice}. Who should I book this for (full name)?`,
            };
          } catch (error) {
            console.error('Flight revalidation error:', error);
            return { reply: 'Could not revalidate your selected flight right now. Please try again.' };
          }
        }

        // Non-flight path (hotels) or no revalidation needed
        sess.choice = selected;
        sess.state = 'awaiting_name';
        return {
          reply: `Excellent choice! ${selected?.name ?? 'Selected item'} is a great option. Now, who should I book this for? (Please provide your full name)`,
        };
      }

      return { reply: "I couldn't find that option. Please select from the list above." };
    }

    // --- STEP 5: HANDLE NUMBER SELECTION (from card UI) ---
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

    // --- STEP 7: POST-BOOKING YES/NO CONTROL ---
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
      if (
        (text.includes('another') &&
          (text.includes('booking') || text.includes('search') || text.includes('again'))) ||
        text === 'yes'
      ) {
        this.sessions.set(sessionId, {
          state: 'idle',
          bookingType: undefined,
        });
        return {
          reply: 'Great! Would you like to book a flight or a hotel?',
        };
      }
    }

    // --- STEP 8: RESET FOR NEW BOOKING (general) ---
    if (
      (text.includes('another') &&
        (text.includes('booking') || text.includes('search') || text.includes('again'))) ||
      text === 'yes'
    ) {
      this.sessions.set(sessionId, {
        state: 'idle',
        bookingType: undefined,
      });
      return {
        reply: 'Great! Would you like to book a flight or a hotel?',
      };
    }

    // --- FALLBACK ---
    return {
      reply: `I'm here to help! What would you like to do:\n• Book a flight\n• Book a hotel\n\nJust tell me the details!`,
    };
  }
}