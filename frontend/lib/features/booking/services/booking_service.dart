import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/booking_models.dart';

class BookingService {
  final String baseUrl;

  BookingService({required this.baseUrl});

  /// Revalidate hotel availability and get token
  Future<RevalidationResult> revalidateHotel({
    required String token,
    required String recommendationId,
    required String hotelId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/revalidate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'recommendationId': recommendationId,
          'hotelId': hotelId,
        }),
      );

      debugPrint('Revalidation response status: ${response.statusCode}');
      debugPrint('Revalidation response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) {
          return RevalidationResult(
            success: true,
            token: token.isNotEmpty ? token : null,
            message: 'Revalidation success (empty body, status ${response.statusCode})',
            rawData: response.body,
          );
        }

        try {
          final data = json.decode(response.body);
          return RevalidationResult.fromJson(data);
        } catch (decodeError, st) {
          debugPrint('Revalidation parse error: $decodeError\n$st');
          return RevalidationResult(
            success: true,
            token: token.isNotEmpty ? token : null,
            message: 'Revalidation success with non-JSON body',
            rawData: response.body,
          );
        }
      } else {
        return RevalidationResult(
          success: false,
          message: 'Failed to revalidate: ${response.statusCode}',
          rawData: response.body,
        );
      }
    } catch (e, st) {
      debugPrint('Revalidation error: $e\n$st');
      return RevalidationResult(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Get rooms and rates for the hotel
  Future<List<RoomRate>> getRoomsAndRates({
    required String hotelId,
    String token = '',
    String checkIn = '',
    String checkOut = '',
    List<dynamic>? rooms,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/get-rooms-and-rates'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'hotelId': hotelId,
          if (checkIn.isNotEmpty) 'checkIn': checkIn,
          if (checkOut.isNotEmpty) 'checkOut': checkOut,
          if (rooms != null && rooms.isNotEmpty) 'rooms': rooms,
        }),
      );

      debugPrint('Rooms/Rates response status: ${response.statusCode}');
      debugPrint('Rooms/Rates response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) {
          return [];
        }

        try {
          final data = json.decode(response.body);
          final roomsList = _extractRooms(data);
          return roomsList.map((room) => RoomRate.fromJson(room)).toList();
        } catch (decodeError, st) {
          debugPrint('Rooms/Rates parse error: $decodeError\n$st');
          return [];
        }
      } else {
        debugPrint('Failed to get rooms: ${response.statusCode}');
        return [];
      }
    } catch (e, st) {
      debugPrint('Get rooms/rates error: $e\n$st');
      return [];
    }
  }

  /// Get payment URL for the booking
  Future<PaymentResult> getPaymentUrl({
    required String token,
    required String hotelId,
    required String roomId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/get-payment-url'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'hotelId': hotelId,
          'roomId': roomId,
        }),
      );

      debugPrint('Payment URL response status: ${response.statusCode}');
      debugPrint('Payment URL response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return PaymentResult.fromJson(data);
      } else {
        return PaymentResult(
          success: false,
          message: 'Failed to get payment URL: ${response.statusCode}',
          rawData: response.body,
        );
      }
    } catch (e, st) {
      debugPrint('Get payment URL error: $e\n$st');
      return PaymentResult(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Revalidate selected flight
  Future<dynamic> revalidateFlight({
    required String fareSourceCode,
    required num key0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/flight/revalidate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fareSourceCode': fareSourceCode,
          'key_0': key0,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) return {'success': true};
        return json.decode(response.body);
      }

      return {
        'success': false,
        'message': 'Failed to revalidate flight: ${response.statusCode}',
        'rawData': response.body,
      };
    } catch (e, st) {
      debugPrint('Flight revalidation error: $e\n$st');
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Get payment URL for selected flight
  Future<dynamic> getFlightPaymentUrl({
    required String fareSourceCode,
    required num key0,
    dynamic revalidateResult,
    dynamic selectedFlight,
    String? origin,
    String? destination,
    String? departureDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/flight/get-payment-url'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fareSourceCode': fareSourceCode,
          'key_0': key0,
          'key0': key0,
          'revalidateResult': revalidateResult,
          'priceCheckResult': revalidateResult,
          'selectedFlight': selectedFlight,
          if (origin != null && origin.isNotEmpty) 'origin': origin,
          if (destination != null && destination.isNotEmpty) 'destination': destination,
          if (departureDate != null && departureDate.isNotEmpty) 'departureDate': departureDate,
          'portalUrl': 'https://routestack.ai',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) return {'success': false};
        return json.decode(response.body);
      }

      return {
        'success': false,
        'message': 'Failed to get flight payment URL: ${response.statusCode}',
        'rawData': response.body,
      };
    } catch (e, st) {
      debugPrint('Flight payment URL error: $e\n$st');
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Create a booking record and return backend booking ID
  Future<String?> createBookingRecord({
    required String name,
    required String type,
    required String itemId,
    String? details,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/book'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'type': type,
          'itemId': itemId,
          if (details != null && details.isNotEmpty) 'details': details,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data is Map ? data['id']?.toString() : null;
      }

      debugPrint('Failed to create booking record: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('Create booking record error: $e\n$st');
      return null;
    }
  }

  /// Get hotel details (fallback for revalidate token/recommendationId)
  Future<dynamic> getHotelDetails(String hotelId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/get-hotel-details'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'hotelId': hotelId}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      }

      debugPrint('Failed to get hotel details: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('Error fetching hotel details: $e\n$st');
      return null;
    }
  }

  /// Extract rooms from API response
  List<dynamic> _extractRooms(dynamic data) {
    if (data is Map) {
      final rooms = data['result']?['rooms'];
      if (rooms is List) return rooms;
      
      final directRooms = data['rooms'];
      if (directRooms is List) return directRooms;
    }
    return [];
  }
}
