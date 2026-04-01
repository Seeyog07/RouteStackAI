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
