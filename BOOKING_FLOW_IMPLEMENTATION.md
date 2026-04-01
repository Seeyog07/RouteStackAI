# Hotel Booking Flow - Implementation Guide

## Overview
A complete hotel booking flow has been implemented that handles:
1. **Hotel Revalidation** - Verify availability when user selects a hotel
2. **Room & Rate Fetching** - Display available rooms with pricing
3. **Room Selection** - Let user pick their preferred room
4. **Payment Integration** - Generate payment URL and redirect to payment

## Architecture

### Models (`features/booking/models/booking_models.dart`)
- `RevalidationResult` - Handles revalidation API response
- `RoomRate` - Represents a single room with pricing and policies
- `BookingDetails` - Container for complete booking information
- `PaymentResult` - Handles payment URL generation response

### Service (`features/booking/services/booking_service.dart`)
```dart
BookingService {
  revalidateHotel()          // POST /mcp/hotel/revalidate
  getRoomsAndRates()         // POST /mcp/hotel/get-rooms-and-rates
  getPaymentUrl()            // POST /mcp/hotel/get-payment-url
}
```

### UI Widget (`features/booking/widgets/booking_confirmation_dialog.dart`)
Beautiful booking confirmation dialog showing:
- Hotel summary info
- Available rooms with pricing
- Cancellation policies
- Room selection radio buttons
- Payment button

## API Endpoints Used

### 1. Revalidation
**Endpoint**: `https://mcp.routestack.ai/mcp/hotel/revalidate`
**Method**: POST
**Body**:
```json
{
  "hotelId": "string",
  "destinationId": "string"
}
```
**Response**:
```json
{
  "success": true,
  "token": "revalidation_token_123"
}
```

### 2. Get Rooms and Rates
**Endpoint**: `https://mcp.routestack.ai/mcp/hotel/get-rooms-and-rates`
**Method**: POST
**Body**:
```json
{
  "token": "revalidation_token_123",
  "hotelId": "hotel_id_123"
}
```
**Response**:
```json
{
  "result": {
    "rooms": [
      {
        "id": "room_id_123",
        "name": "Deluxe Double",
        "descriptions": {
          "overview": "Spacious room with king bed..."
        },
        "occupancy": {
          "max_allowed": {
            "total": 2
          }
        },
        "rates": [
          {
            "total": {
              "amount": "150",
              "currency": "USD"
            },
            "cancellation_policy": {
              "description": "Free cancellation up to 24h..."
            }
          }
        ]
      }
    ]
  }
}
```

### 3. Get Payment URL
**Endpoint**: `https://mcp.routestack.ai/mcp/hotel/get-payment-url`
**Method**: POST
**Body**:
```json
{
  "token": "revalidation_token_123",
  "hotelId": "hotel_id_123",
  "roomId": "room_id_123"
}
```
**Response**:
```json
{
  "success": true,
  "paymentUrl": "https://payment.example.com/checkout?session=xyz"
}
```

## User Flow

1. **Hotel Search & Selection**
   - User searches for hotels
   - User clicks "Select This Hotel" button in hotel details dialog
   - `_selectCard()` function is triggered

2. **Booking Confirmation Dialog Opens**
   - Hotel summary is displayed at the top
   - BookingService initiates revalidation request
   - Getting rooms and rates data fetches available options

3. **Room Selection**
   - User sees all available rooms
   - Each room displays:
     - Room name
     - Max occupancy
     - Price per night
     - Cancellation policy
     - Description
   - User selects preferred room via radio button

4. **Payment**
   - User clicks "Proceed to Payment"
   - System fetches payment URL using the revalidation token and selected room
   - User is redirected to payment gateway
   - External payment processing occurs

## File Structure
```
frontend/lib/
├── features/
│   ├── booking/
│   │   ├── models/
│   │   │   └── booking_models.dart
│   │   ├── services/
│   │   │   └── booking_service.dart
│   │   └── widgets/
│   │       └── booking_confirmation_dialog.dart
│   └── hotel_details/
│       ├── models/
│       ├── viewmodels/
│       └── widgets/
└── main.dart (updated)
```

## Key Features

### 1. Revalidation Handling
- Validates hotel availability when selected
- Gets revalidation token for subsequent API calls
- Error handling with user-friendly messages

### 2. Room Display
- Shows all available rooms with complete information
- Price formatting (currency + amount)
- Occupancy information
- Cancellation policy warnings

### 3. User Selection
- Radio buttons for room selection
- Visual feedback for selected room
- Card highlights with indigo border when selected

### 4. Payment Integration
- Seamless redirect to payment provider
- External application launch using `url_launcher`
- Loading state during payment URL generation
- Error handling and user notifications

### 5. State Management
- FutureBuilder for loading API responses
- Async/await for clean async code
- ScaffoldMessenger for error notifications
- SetState for UI updates

## UI Components

### BookingConfirmationDialog
Main dialog with multiple sections:

**Header**
- Hotel name and title
- Close button

**Body**
- Hotel summary (ID, price, revalidated status)
- Rooms section with room cards
- Each room card shows:
  - Radio button for selection
  - Room name and occupancy
  - Price with CSS styling
  - Description
  - Cancellation policy box

**Footer**
- Cancel button
- Proceed to Payment button (with loading indicator)

## Error Handling

1. **Network Errors**
   - Caught in try-catch blocks
   - User-friendly error messages
   - ScaffoldMessenger notifications

2. **API Errors**
   - Status code checks
   - Fallback error messages
   - Detailed logging for debugging

3. **Payment Errors**
   - URL launch validation
   - Payment URL missing handling
   - External app launch failures

## Dependencies Added
```yaml
url_launcher: ^6.1.0  # For opening payment URLs
```

## Testing Checklist

1. **Hotel Selection**
   - [ ] Select a hotel from search results
   - [ ] Booking confirmation dialog opens
   - [ ] Dialog shows loading state initially

2. **Revalidation**
   - [ ] Hotel revalidates successfully
   - [ ] Error message shows if revalidation fails
   - [ ] Check console for API responses

3. **Room Display**
   - [ ] All available rooms display
   - [ ] Room details show correctly
   - [ ] Pricing formatted properly
   - [ ] Cancellation policies visible

4. **Room Selection**
   - [ ] Can select different rooms
   - [ ] Visual feedback on selection
   - [ ] Cannot proceed without selection

5. **Payment Flow**
   - [ ] Payment URL fetches correctly
   - [ ] User redirected to payment site
   - [ ] Error shown if URL generation fails
   - [ ] Loading indicator shows during fetch

6. **Dialog Management**
   - [ ] Can close dialog with X button
   - [ ] Can click cancel to abort
   - [ ] Dialog transitions smoothly
   - [ ] Proper cleanup on close

## Future Enhancements

- [ ] Add guest information form
- [ ] Calculate total cost (check-in to check-out nights)
- [ ] Add multiple room selection
- [ ] Save booking as draft
- [ ] Send confirmation email
- [ ] Add booking receipt view
- [ ] Implement coupon/promo codes
- [ ] Add booking insurance options
- [ ] Integration with loyalty programs
- [ ] Payment method selection before redirect

## Important Notes

- The revalidation token is time-sensitive and should be used immediately
- Always validate hotel availability using revalidation before payment
- Payment URL should open in external application for security
- All API endpoints use MCP protocol with specific request/response formats
- Debug logs show all API calls for troubleshooting

---

**Implementation Date**: April 1, 2026
**Status**: ✅ Complete and ready for testing
