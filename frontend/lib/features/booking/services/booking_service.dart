import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/booking_models.dart';

class BookingService {
  final String baseUrl;

  BookingService({required this.baseUrl});

  String _encodeBody(Map<String, dynamic> body) => json.encode(body);

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
            message:
                'Revalidation success (empty body, status ${response.statusCode})',
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
    String? correlationId,
    List<dynamic>? rooms,
  }) async {
    try {
      final today = DateTime.now();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final effectiveCheckIn = checkIn.isNotEmpty
          ? checkIn
          : '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final effectiveCheckOut = checkOut.isNotEmpty
          ? checkOut
          : '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      final effectiveRooms = (rooms != null && rooms.isNotEmpty)
          ? rooms
          : [
              {
                'childAges': [],
                'children': 0,
                'adults': 2,
              }
            ];

      debugPrint(
        'Calling /mcp/hotel/get-hotel-details-and-rates for hotelId=$hotelId',
      );

      final data = await getHotelDetailsAndRates(
        hotelId: hotelId,
        token: token,
        checkIn: effectiveCheckIn,
        checkOut: effectiveCheckOut,
        correlationId: correlationId,
        rooms: effectiveRooms,
      );

      if (data == null) {
        return [];
      }

      return parseRoomRates(data);
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
    String? recommendationId,
    String? checkIn,
    String? checkOut,
    Map<String, dynamic>? priceCheckResult,
    String? hotelName,
    String? hotelAddress,
    String? hotelImage,
    dynamic hotelLatitude,
    dynamic hotelLongitude,
    dynamic hotelStarRating,
    dynamic hotelRating,
    String? correlationId,
    double? displayedPrice,
    List<Map<String, dynamic>>? travellers,
    Map<String, dynamic>? destination,
  }) async {
    try {
      final body = <String, dynamic>{
        'token': token,
        'hotelId': hotelId,
        'roomId': roomId,
        if (recommendationId != null && recommendationId.isNotEmpty)
          'recommendationId': recommendationId,
        if (checkIn != null && checkIn.isNotEmpty) 'checkIn': checkIn,
        if (checkOut != null && checkOut.isNotEmpty) 'checkOut': checkOut,
        if (priceCheckResult != null) 'priceCheckResult': priceCheckResult,
        if (hotelName != null && hotelName.isNotEmpty) 'hotelName': hotelName,
        if (hotelAddress != null && hotelAddress.isNotEmpty)
          'hotelAddress': hotelAddress,
        if (hotelImage != null && hotelImage.isNotEmpty)
          'hotelImage': hotelImage,
        if (hotelLatitude != null) 'hotelLatitude': hotelLatitude,
        if (hotelLongitude != null) 'hotelLongitude': hotelLongitude,
        if (hotelStarRating != null) 'hotelStarRating': hotelStarRating,
        if (hotelRating != null) 'hotelRating': hotelRating,
        if (correlationId != null && correlationId.isNotEmpty)
          'correlationId': correlationId,
        if (displayedPrice != null) 'displayedPrice': displayedPrice,
        if (travellers != null && travellers.isNotEmpty)
          'travellers': travellers,
        if (destination != null) 'destination': destination,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/get-payment-url'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
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
          if (destination != null && destination.isNotEmpty)
            'destination': destination,
          if (departureDate != null && departureDate.isNotEmpty)
            'departureDate': departureDate,
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

  /// Search destinations for hotel flow
  Future<dynamic> searchHotelDestinations({
    required String query,
    String type = 'DESTINATION',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/search-destinations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'type': type,
          'query': query,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) return null;
        return json.decode(response.body);
      }

      debugPrint('Failed to search destinations: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('Error searching destinations: $e\n$st');
      return null;
    }
  }

  /// Search hotels directly via MCP endpoint
  Future<dynamic> searchHotels({
    required String destinationId,
    required String checkIn,
    required String checkOut,
    required List<dynamic> rooms,
    required double lat,
    required double long,
    String currency = 'USD',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/search-hotels'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'destinationId': destinationId,
          'checkIn': checkIn,
          'checkOut': checkOut,
          'rooms': rooms,
          'lat': lat,
          'long': long,
          'currency': currency,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) return null;
        return json.decode(response.body);
      }

      debugPrint('Failed to search hotels: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('Error searching hotels: $e\n$st');
      return null;
    }
  }

  /// Get hotel details and rates in one call when user selects a hotel
  Future<dynamic> getHotelDetailsAndRates({
    required String hotelId,
    required String token,
    required String checkIn,
    required String checkOut,
    required List<dynamic> rooms,
    String? correlationId,
    String? contentType,
    String? hotelName,
    num? publishedRate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mcp/hotel/get-hotel-details-and-rates'),
        headers: {'Content-Type': 'application/json'},
        body: _encodeBody({
          'hotelId': hotelId,
          'token': token,
          'checkIn': checkIn,
          'checkOut': checkOut,
          'rooms': rooms,
          if (correlationId != null && correlationId.isNotEmpty)
            'correlationId': correlationId,
          if (contentType != null && contentType.isNotEmpty)
            'contentType': contentType,
          if (hotelName != null && hotelName.isNotEmpty) 'hotelName': hotelName,
          if (publishedRate != null) 'publishedRate': publishedRate,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.trim().isEmpty) return null;
        return json.decode(response.body);
      }

      debugPrint(
          'Failed to get hotel details and rates: ${response.statusCode}');
      return null;
    } catch (e, st) {
      debugPrint('Error getting hotel details and rates: $e\n$st');
      return null;
    }
  }

  /// Convert hotel details/rates API payload to room-rate models
  List<RoomRate> parseRoomRates(dynamic data) {
    final roomsList = _extractRooms(data);
    return roomsList.map((room) => RoomRate.fromJson(room)).toList();
  }

  /// Extract rooms from API response
  List<dynamic> _extractRooms(dynamic data) {
    if (data is Map) {
      final result = data['result'];

      // Primary shape: result.rooms list
      final rooms = result?['rooms'];
      if (rooms is List) return rooms;

      if (result is Map) {
        final contentRooms = result['content']?['rooms'];
        final availability = result['availability'];

        // Preferred shape: result.availability.groups[].rooms[]
        final groups = availability?['groups'];
        if (groups is List && groups.isNotEmpty) {
          final contentByName = <String, Map<String, dynamic>>{};
          final contentById = <String, Map<String, dynamic>>{};

          if (contentRooms is Map) {
            for (final entry in contentRooms.entries) {
              if (entry.value is! Map) continue;
              final room = Map<String, dynamic>.from(entry.value as Map);
              final id = room['id']?.toString() ?? entry.key.toString();
              final name = room['name']?.toString() ?? '';
              if (id.isNotEmpty) contentById[id] = room;
              if (name.isNotEmpty) contentByName[name] = room;
            }
          }

          final extracted = <dynamic>[];
          final byRoomKey = <String, Map<String, dynamic>>{};

          double _priceOf(Map<String, dynamic> room) {
            final rates = room['rates'];
            if (rates is List && rates.isNotEmpty && rates.first is Map) {
              final amount =
                  (rates.first as Map)['total']?['amount']?.toString();
              return double.tryParse(amount ?? '') ?? double.infinity;
            }
            return double.infinity;
          }

          for (final g in groups) {
            if (g is! Map) continue;
            final groupRooms = g['rooms'];
            if (groupRooms is! List) continue;

            for (final r in groupRooms) {
              if (r is! Map) continue;
              final availabilityRoom = Map<String, dynamic>.from(r);
              final roomName = availabilityRoom['name']?.toString() ??
                  g['type']?.toString() ??
                  'Room';
              final contentMatch = contentByName[roomName] ??
                  contentById[availabilityRoom['id']?.toString() ?? ''];
              final recommendationId =
                  availabilityRoom['recommendationId']?.toString() ??
                      contentMatch?['recommendationId']?.toString();

              final merged = <String, dynamic>{
                'id': availabilityRoom['id']?.toString() ??
                    contentMatch?['id']?.toString() ??
                    '',
                'name': roomName,
                if (recommendationId != null && recommendationId.isNotEmpty)
                  'recommendationId': recommendationId,
                if (contentMatch?['descriptions'] != null)
                  'descriptions': contentMatch!['descriptions'],
                if (contentMatch?['occupancy'] != null)
                  'occupancy': contentMatch!['occupancy'],
                if (contentMatch?['bed_groups'] != null)
                  'bed_groups': contentMatch!['bed_groups'],
                if (contentMatch?['amenities'] != null)
                  'amenities': contentMatch!['amenities'],
                'rates': [
                  {
                    'total': {
                      'amount': (availabilityRoom['ourprice'] ??
                              availabilityRoom['publishedRate'] ??
                              availabilityRoom['totalRate'] ??
                              availabilityRoom['baseRate'])
                          ?.toString(),
                      'currency':
                          availability?['currency']?.toString() ?? 'USD',
                    },
                    'cancellation_policy': {
                      'description':
                          availabilityRoom['refundability']?.toString() ??
                              (availabilityRoom['refundable'] == true
                                  ? 'Refundable'
                                  : 'Non-refundable'),
                    },
                  }
                ],
              };

              final dedupeKey = (merged['id']?.toString().isNotEmpty == true)
                  ? merged['id'].toString()
                  : 'name:${roomName.toLowerCase()}';
              final existing = byRoomKey[dedupeKey];

              if (existing == null || _priceOf(merged) < _priceOf(existing)) {
                byRoomKey[dedupeKey] = merged;
              }
            }
          }

          extracted.addAll(byRoomKey.values);

          if (extracted.isNotEmpty) return extracted;
        }

        // Common partial shape: result.content.rooms keyed by roomId
        if (contentRooms is Map) {
          final ratesMap = result['content']?['rates'];

          return contentRooms.entries
              .where((entry) => entry.value is Map)
              .map((entry) {
            final roomId = entry.key.toString();
            final room = Map<String, dynamic>.from(entry.value as Map);

            final candidateRates = <dynamic>[];

            final availabilityRooms = availability?['rooms'];
            if (availabilityRooms is Map && availabilityRooms[roomId] is Map) {
              final roomAvailability = availabilityRooms[roomId] as Map;
              if (roomAvailability['rates'] is List) {
                candidateRates.addAll(roomAvailability['rates'] as List);
              }
            }

            // Fallback to attach any known rates for amenity/cancellation metadata
            if (candidateRates.isEmpty && ratesMap is Map) {
              candidateRates.addAll(ratesMap.values.whereType<Map>());
            }

            room['id'] = room['id']?.toString() ?? roomId;
            room['rates'] = candidateRates;
            return room;
          }).toList();
        }

        if (contentRooms is List) {
          return contentRooms;
        }
      }

      final directRooms = data['rooms'];
      if (directRooms is List) return directRooms;
    }
    return [];
  }
}
