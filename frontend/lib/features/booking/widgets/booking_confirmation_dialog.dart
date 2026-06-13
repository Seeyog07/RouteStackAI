import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/booking_models.dart';
import '../services/booking_service.dart';

/// Booking confirmation dialog showing hotel details, rooms, rates, and payment option
class BookingConfirmationDialog extends StatefulWidget {
  final dynamic hotel;
  final BookingService bookingService;
  final VoidCallback? onClose;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onBookingConfirmed;

  const BookingConfirmationDialog({
    Key? key,
    required this.hotel,
    required this.bookingService,
    this.onClose,
    this.onCancel,
    this.onBookingConfirmed,
  }) : super(key: key);

  @override
  State<BookingConfirmationDialog> createState() =>
      _BookingConfirmationDialogState();
}

class _BookingConfirmationDialogState extends State<BookingConfirmationDialog> {
  late Future<BookingDetails> _bookingDetailsFuture;
  String? _selectedRoomId;
  bool _isProcessingPayment = false;

  double _toDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<Map<String, dynamic>?> _searchHotelsFirst({
    required String destinationId,
    required String checkIn,
    required String checkOut,
    required List<dynamic> rooms,
    required String selectedHotelId,
  }) async {
    final geo = widget.hotel['geoCode'];
    final coordinates = widget.hotel['coordinates'];

    final lat = _toDouble(
      widget.hotel['lat'] ??
          widget.hotel['latitude'] ??
          (geo is Map ? geo['lat'] : null) ??
          (coordinates is Map ? coordinates['lat'] : null),
      0.0,
    );
    final long = _toDouble(
      widget.hotel['long'] ??
          widget.hotel['longitude'] ??
          (geo is Map ? geo['long'] : null) ??
          (coordinates is Map ? coordinates['long'] : null),
      0.0,
    );

    final searchResp = await widget.bookingService.searchHotels(
      destinationId: destinationId,
      checkIn: checkIn,
      checkOut: checkOut,
      rooms: rooms,
      lat: lat,
      long: long,
    );

    if (searchResp is! Map) return null;

    final resultMap =
        searchResp['result'] is Map ? searchResp['result'] as Map : searchResp;
    final hotels = resultMap['result'] is List
        ? resultMap['result'] as List
        : (resultMap['hotels'] is List
            ? resultMap['hotels'] as List
            : <dynamic>[]);

    Map<String, dynamic>? matchedHotel;
    for (final h in hotels) {
      if (h is! Map) continue;
      final candidateId = h['id']?.toString() ?? h['hotelId']?.toString();
      if (candidateId == selectedHotelId) {
        matchedHotel = Map<String, dynamic>.from(h);
        break;
      }
    }

    final freshToken = matchedHotel?['token']?.toString() ??
        matchedHotel?['hotelToken']?.toString() ??
        resultMap['token']?.toString();
    final freshRecommendationId = matchedHotel?['recommendationId']?.toString();

    return {
      if (freshToken != null && freshToken.isNotEmpty) 'token': freshToken,
      if (freshRecommendationId != null && freshRecommendationId.isNotEmpty)
        'recommendationId': freshRecommendationId,
      if (resultMap['correlationId'] != null)
        'correlationId': resultMap['correlationId'].toString(),
      if (destinationId.isNotEmpty) 'destinationId': destinationId,
    };
  }

  Future<String> _resolveDestinationId(String fallbackQuery) async {
    final query = fallbackQuery.trim();
    if (query.isEmpty) return '';

    final destinationResp =
        await widget.bookingService.searchHotelDestinations(query: query);
    if (destinationResp is! Map) return '';

    final result = destinationResp['result'];
    if (result is List && result.isNotEmpty && result.first is Map) {
      return result.first['id']?.toString() ?? '';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _bookingDetailsFuture = _loadBookingDetails();
  }

  Future<BookingDetails> _loadBookingDetails() async {
    final hotelId = widget.hotel['id'] ?? '';

    String token = widget.hotel['token'] ?? widget.hotel['hotelToken'] ?? '';
    String recommendationId = widget.hotel['recommendationId'] ??
        widget.hotel['correlationId']?.toString() ??
        '';

    // Fetch hotel details for token/recommendation if missing
    if ((token.isEmpty || recommendationId.isEmpty) && hotelId.isNotEmpty) {
      final details = await widget.bookingService.getHotelDetails(
        hotelId: hotelId,
        token: widget.hotel['token']?.toString() ??
            widget.hotel['hotelToken']?.toString() ??
            '',
        correlationId: widget.hotel['correlationId']?.toString() ?? '',
        contentType: 'ALL',
      );
      if (details is Map) {
        token = token.isNotEmpty
            ? token
            : (details['token'] ??
                details['result']?['token'] ??
                details['hotelToken'] ??
                '');
        recommendationId = recommendationId.isNotEmpty
            ? recommendationId
            : (details['recommendationId'] ??
                details['result']?['recommendationId'] ??
                '');
      }
    }

    debugPrint(
        'Booking confirm: hotelId=$hotelId token=$token recommendationId=$recommendationId');

    // Extract check-in/check-out from hotel object if available
    String checkIn = widget.hotel['checkIn']?.toString() ?? '';
    String checkOut = widget.hotel['checkOut']?.toString() ?? '';

    if (checkIn.isEmpty || checkOut.isEmpty) {
      throw Exception(
        'Missing trip dates for this hotel. Please search hotels again and select the same property.',
      );
    }

    // Default rooms config if not in hotel object
    final roomsConfig = widget.hotel['rooms'] ??
        [
          {
            'childAges': [],
            'children': 0,
            'adults': 2,
          }
        ];

    // Call search-hotels first to refresh the token/context before room details.
    String destinationId = widget.hotel['destinationId']?.toString() ??
        widget.hotel['destination']?['id']?.toString() ??
        '';
    String correlationId = widget.hotel['correlationId']?.toString() ?? '';

    if (destinationId.isEmpty) {
      final cityHint = widget.hotel['city']?.toString() ??
          widget.hotel['destinationName']?.toString() ??
          widget.hotel['name']?.toString() ??
          '';
      destinationId = await _resolveDestinationId(cityHint);
    }

    if (destinationId.isNotEmpty) {
      final freshContext = await _searchHotelsFirst(
        destinationId: destinationId,
        checkIn: checkIn,
        checkOut: checkOut,
        rooms: roomsConfig,
        selectedHotelId: hotelId,
      );

      if (freshContext != null) {
        token = freshContext['token']?.toString() ?? token;
        recommendationId =
            freshContext['recommendationId']?.toString() ?? recommendationId;
        destinationId =
            freshContext['destinationId']?.toString() ?? destinationId;
        correlationId =
            freshContext['correlationId']?.toString() ?? correlationId;
      }
    }

    debugPrint(
      'Room flow: after search-hotels hotelId=$hotelId token=$token recommendationId=$recommendationId',
    );

    // Revalidate before calling get-hotel-details-and-rates.
    final revalidateRecommendationId =
        recommendationId.isNotEmpty ? recommendationId : correlationId;
    if (token.isNotEmpty && revalidateRecommendationId.isNotEmpty) {
      final revalidateResult = await widget.bookingService.revalidateHotel(
        token: token,
        recommendationId: revalidateRecommendationId,
        hotelId: hotelId,
      );

      if (revalidateResult.success &&
          revalidateResult.token != null &&
          revalidateResult.token!.isNotEmpty) {
        token = revalidateResult.token!;
      }

      debugPrint(
        'Room flow: revalidate status=${revalidateResult.success} token=${revalidateResult.token ?? token}',
      );
    } else {
      debugPrint(
        'Room flow: skipping revalidate (missing token or recommendation/correlation id)',
      );
    }

    // After selecting a hotel, load room options using get-hotel-details-and-rates.
    final rooms = await widget.bookingService.getRoomsAndRates(
      hotelId: hotelId,
      token: token,
      checkIn: checkIn,
      checkOut: checkOut,
      correlationId: correlationId,
      rooms: roomsConfig,
    );

    // If no rooms returned (commonly expired offer), refresh token once and retry.
    List<RoomRate> effectiveRooms = rooms;
    if (effectiveRooms.isEmpty && destinationId.isNotEmpty) {
      final retryContext = await _searchHotelsFirst(
        destinationId: destinationId,
        checkIn: checkIn,
        checkOut: checkOut,
        rooms: roomsConfig,
        selectedHotelId: hotelId,
      );
      if (retryContext != null) {
        token = retryContext['token']?.toString() ?? token;
        recommendationId =
            retryContext['recommendationId']?.toString() ?? recommendationId;
        correlationId =
            retryContext['correlationId']?.toString() ?? correlationId;
      }

      final retryRevalidateRecommendationId =
          recommendationId.isNotEmpty ? recommendationId : correlationId;
      if (token.isNotEmpty && retryRevalidateRecommendationId.isNotEmpty) {
        final retryRevalidate = await widget.bookingService.revalidateHotel(
          token: token,
          recommendationId: retryRevalidateRecommendationId,
          hotelId: hotelId,
        );
        if (retryRevalidate.success &&
            retryRevalidate.token != null &&
            retryRevalidate.token!.isNotEmpty) {
          token = retryRevalidate.token!;
        }
      }

      effectiveRooms = await widget.bookingService.getRoomsAndRates(
        hotelId: hotelId,
        token: token,
        checkIn: checkIn,
        checkOut: checkOut,
        correlationId: correlationId,
        rooms: roomsConfig,
      );
    }

    final effectiveHotel = widget.hotel is Map
        ? {
            ...widget.hotel,
            'token': token,
            'recommendationId': recommendationId,
            'checkIn': checkIn,
            'checkOut': checkOut,
            'rooms': roomsConfig,
            if (destinationId.isNotEmpty) 'destinationId': destinationId,
            if (correlationId.isNotEmpty) 'correlationId': correlationId,
          }
        : widget.hotel;

    // Keep valid state so the dialog can render room options only.
    final revalidation = RevalidationResult(
      success: true,
      token: token,
      message: 'Ready for room selection',
      rawData: {'source': 'get-hotel-details-and-rates'},
    );

    return BookingDetails(
      hotel: effectiveHotel,
      revalidation: revalidation,
      rooms: effectiveRooms,
    );
  }

  Future<void> _proceedToPayment(
    BuildContext context,
    BookingDetails booking,
  ) async {
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a room')),
      );
      return;
    }

    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);

    try {
      final room = booking.rooms.firstWhere(
        (r) => r.roomId == _selectedRoomId,
        orElse: () => booking.rooms.first,
      );

      final hotelId = booking.hotel['id']?.toString() ?? '';
      var token = booking.revalidation.token?.toString() ??
          booking.hotel['token']?.toString() ??
          booking.hotel['hotelToken']?.toString() ??
          '';
      final recommendationId = room.recommendationId ??
          booking.hotel['recommendationId']?.toString() ??
          booking.hotel['correlationId']?.toString() ??
          '';
      final checkIn = booking.hotel['checkIn']?.toString() ?? '';
      final checkOut = booking.hotel['checkOut']?.toString() ?? '';

      if (hotelId.isEmpty ||
          token.isEmpty ||
          recommendationId.isEmpty ||
          checkIn.isEmpty ||
          checkOut.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Missing hotel context. Please select the hotel again.'),
            ),
          );
        }
        return;
      }

      final revalidateResult = await widget.bookingService.revalidateHotel(
        token: token,
        recommendationId: recommendationId,
        hotelId: hotelId,
      );

      if (revalidateResult.success &&
          revalidateResult.token != null &&
          revalidateResult.token!.isNotEmpty) {
        token = revalidateResult.token!;
      }

      final paymentResult = await widget.bookingService.getPaymentUrl(
        token: token,
        hotelId: hotelId,
        roomId: room.roomId,
        recommendationId: recommendationId,
        checkIn: checkIn,
        checkOut: checkOut,
        correlationId: booking.hotel['correlationId']?.toString(),
        displayedPrice: double.tryParse(room.priceAmount ?? ''),
        hotelName: booking.hotelName,
        hotelAddress: booking.hotel['address']?.toString(),
        hotelImage: booking.hotel['heroImage']?.toString(),
        hotelStarRating: booking.hotel['starRating'],
        hotelRating: booking.hotel['rating'],
      );

      if (paymentResult.success && paymentResult.paymentUrl != null) {
        final bookingId = await widget.bookingService.createBookingRecord(
          name: 'Hotel Guest',
          type: 'hotel',
          itemId: booking.hotel['id']?.toString() ?? 'unknown_hotel',
          details:
              'Room: ${room.roomName}, Hotel: ${booking.hotelName ?? 'Unknown'}',
        );

        final url = Uri.parse(paymentResult.paymentUrl!);
        if (!await canLaunchUrl(url)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open payment URL')),
            );
          }
          return;
        }

        await launchUrl(url, mode: LaunchMode.externalApplication);

        if (mounted) {
          if (bookingId != null && bookingId.isNotEmpty) {
            widget.onBookingConfirmed?.call(bookingId);
          }
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                paymentResult.message ?? 'Failed to get payment URL',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BookingDetails>(
      future: _bookingDetailsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingDialog();
        }

        if (snapshot.hasError) {
          return _buildErrorDialog(context, snapshot.error.toString());
        }

        if (!snapshot.hasData) {
          return _buildErrorDialog(context, 'No data available');
        }

        final booking = snapshot.data!;

        return _buildConfirmationDialog(context, booking);
      },
    );
  }

  /// Build loading dialog
  Widget _buildLoadingDialog() {
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading booking details...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// Build error dialog
  Widget _buildErrorDialog(BuildContext context, String error) {
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              'Booking Error',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build main confirmation dialog
  Widget _buildConfirmationDialog(
    BuildContext context,
    BookingDetails booking,
  ) {
    final screen = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screen.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Header with hotel info
            _buildHeader(booking),
            // Rooms and rates section
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHotelInfo(booking),
                      SizedBox(height: 24),
                      _buildRoomsSection(booking),
                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            _buildFooter(context, booking),
          ],
        ),
      ),
    );
  }

  /// Build footer with action buttons
  Widget _buildFooter(BuildContext context, BookingDetails booking) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isProcessingPayment
                ? null
                : () {
                    Navigator.of(context).pop();
                    (widget.onCancel ?? widget.onClose)?.call();
                  },
            child: Text('Cancel'),
          ),
          SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isProcessingPayment
                ? null
                : () => _proceedToPayment(context, booking),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _isProcessingPayment
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Proceed to Payment',
                    style: TextStyle(color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  /// Build header with hotel name and ID
  Widget _buildHeader(BookingDetails booking) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.hotelName ?? 'Hotel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Confirm your booking',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  Navigator.of(context).pop();
                  (widget.onCancel ?? widget.onClose)?.call();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build hotel information section
  Widget _buildHotelInfo(BookingDetails booking) {
    final address = booking.hotel['address']?.toString();
    final checkIn = booking.hotel['checkIn']?.toString();
    final checkOut = booking.hotel['checkOut']?.toString();
    final starRating = booking.hotel['starRating']?.toString();

    return Card(
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Booking Summary',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.indigo,
              ),
            ),
            SizedBox(height: 8),
            _buildInfoRow('Hotel ID', booking.hotel['id']?.toString() ?? 'N/A'),
            _buildInfoRow('Price',
                booking.hotelPrice != null ? '\$${booking.hotelPrice}' : 'N/A'),
            if (starRating != null && starRating.isNotEmpty)
              _buildInfoRow('Star Rating', starRating),
            if (checkIn != null && checkIn.isNotEmpty)
              _buildInfoRow('Check-in', checkIn),
            if (checkOut != null && checkOut.isNotEmpty)
              _buildInfoRow('Check-out', checkOut),
            if (address != null && address.isNotEmpty)
              _buildInfoRow('Address', address),
            _buildInfoRow('Status', 'Room options loaded'),
          ],
        ),
      ),
    );
  }

  /// Build info row
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// Build rooms section
  Widget _buildRoomsSection(BookingDetails booking) {
    if (booking.rooms.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No rooms available',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a Room',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.indigo,
          ),
        ),
        SizedBox(height: 8),
        ...booking.rooms.asMap().entries.map((entry) {
          final index = entry.key;
          final room = entry.value;
          final isSelected = _selectedRoomId == room.roomId;

          return _buildRoomCard(room, isSelected, index + 1);
        }).toList(),
      ],
    );
  }

  /// Build room card
  Widget _buildRoomCard(RoomRate room, bool isSelected, int index) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedRoomId = room.roomId);
      },
      child: Card(
        margin: EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected ? Colors.indigo : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Radio<String>(
                    value: room.roomId,
                    groupValue: _selectedRoomId,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedRoomId = value);
                      }
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.roomName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (room.maxOccupancy != null)
                          Text(
                            'Max occupancy: ${room.maxOccupancy}',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    room.displayPrice,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              if (room.description != null && room.description!.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  room.description!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (room.bedSummary != null && room.bedSummary!.isNotEmpty) ...[
                SizedBox(height: 6),
                Text(
                  'Beds: ${room.bedSummary}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                ),
              ],
              if (room.maxAdults != null || room.maxChildren != null) ...[
                SizedBox(height: 4),
                Text(
                  'Adults: ${room.maxAdults ?? '-'}  •  Children: ${room.maxChildren ?? '-'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
              if (room.amenities.isNotEmpty) ...[
                SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: room.amenities
                      .map(
                        (amenity) => Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            amenity,
                            style: TextStyle(
                                fontSize: 10, color: Colors.blueGrey[800]),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (room.cancellationPolicy != null &&
                  room.cancellationPolicy!.isNotEmpty) ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Cancellation: ${room.cancellationPolicy}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[800],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if ((room.priceAmount == null || room.priceAmount!.isEmpty) &&
                  room.cancellationPolicy == null) ...[
                SizedBox(height: 8),
                Text(
                  'Price details may update after room selection.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
