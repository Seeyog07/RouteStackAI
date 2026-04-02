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

  @override
  void initState() {
    super.initState();
    _bookingDetailsFuture = _loadBookingDetails();
  }

  Future<BookingDetails> _loadBookingDetails() async {
    final hotelId = widget.hotel['id'] ?? '';

    String token = widget.hotel['token'] ?? widget.hotel['hotelToken'] ?? '';
    String recommendationId = widget.hotel['recommendationId'] ?? widget.hotel['recommendationId'] ?? '';

    // Fetch hotel details for token/recommendation if missing
    if ((token.isEmpty || recommendationId.isEmpty) && hotelId.isNotEmpty) {
      final details = await widget.bookingService.getHotelDetails(hotelId);
      if (details is Map) {
        token = token.isNotEmpty
            ? token
            : (details['token'] ?? details['result']?['token'] ?? details['hotelToken'] ?? '');
        recommendationId = recommendationId.isNotEmpty
            ? recommendationId
            : (details['recommendationId'] ?? details['result']?['recommendationId'] ?? '');
      }
    }

    debugPrint('Booking confirm: hotelId=$hotelId token=$token recommendationId=$recommendationId');

    // Revalidate hotel via backend proxy (token + recommendationId + hotelId)
    final revalidation = await widget.bookingService.revalidateHotel(
      token: token,
      recommendationId: recommendationId,
      hotelId: hotelId,
    );

    // Get rooms and rates (try with revalidated token or hotel details token, or even empty for compatibility)
    List<RoomRate> rooms = [];
    final roomToken = revalidation.token?.isNotEmpty == true
        ? revalidation.token
        : (token.isNotEmpty ? token : null);

    if (revalidation.success) {
      // Extract check-in/check-out from hotel object if available
      final checkIn = widget.hotel['checkIn']?.toString() ?? '';
      final checkOut = widget.hotel['checkOut']?.toString() ?? '';
      
      // Default rooms config if not in hotel object
      final roomsConfig = widget.hotel['rooms'] ?? [
        {
          'childAges': [],
          'children': 0,
          'adults': 2,
        }
      ];

      rooms = await widget.bookingService.getRoomsAndRates(
        hotelId: hotelId,
        token: roomToken ?? '',
        checkIn: checkIn,
        checkOut: checkOut,
        rooms: roomsConfig,
      );
    }

    return BookingDetails(
      hotel: widget.hotel,
      revalidation: revalidation,
      rooms: rooms,
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

    setState(() => _isProcessingPayment = true);

    try {
      final paymentResult = await widget.bookingService.getPaymentUrl(
        token: booking.revalidation.token!,
        hotelId: booking.hotel['id'] ?? '',
        roomId: _selectedRoomId!,
      );

      if (mounted) {
        if (paymentResult.success && paymentResult.paymentUrl != null) {
          final bookingId = await widget.bookingService.createBookingRecord(
            name: 'Hotel Guest',
            type: 'hotel',
            itemId: booking.hotel['id']?.toString() ?? 'unknown_hotel',
            details: 'Room: $_selectedRoomId, Hotel: ${booking.hotelName ?? 'Unknown'}',
          );

          // Launch payment URL
          final url = Uri.parse(paymentResult.paymentUrl!);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);

            if (bookingId != null && bookingId.isNotEmpty) {
              widget.onBookingConfirmed?.call(bookingId);
              Navigator.of(context).pop();
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open payment URL')),
            );
          }
        } else {
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

        if (!booking.isValid) {
          return _buildErrorDialog(
            context,
            booking.revalidation.message ?? 'Failed to revalidate hotel',
          );
        }

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
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with hotel info
            _buildHeader(booking),
            // Rooms and rates section
            Expanded(
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
            // Footer with action buttons
            _buildFooter(context, booking),
          ],
        ),
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
            _buildInfoRow('Price', '\$${booking.hotelPrice}'),
            _buildInfoRow('Status', 'Revalidated ✓'),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
            ],
          ),
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
}
