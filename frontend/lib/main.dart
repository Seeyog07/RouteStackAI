import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'features/hotel_details/models/image_carousel_model.dart';
import 'features/hotel_details/widgets/image_carousel_widget.dart';
import 'features/booking/services/booking_service.dart';
import 'features/booking/widgets/booking_confirmation_dialog.dart';

enum HotelSortMode {
  defaultOrder,
  priceLowToHigh,
  priceHighToLow,
}

enum TripPlannerType {
  hotel,
  flight,
}

void main() => runApp(RouteStackApp());

class RouteStackApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RouteStack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
      ),
      home: HomePage(),
    );
  }
}

class ChatMessage {
  final String? text;
  final bool fromUser;
  final List<dynamic>? cards;
  ChatMessage(this.text, {this.fromUser = false, this.cards});
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ChatMessage> messages = [];
  final ScrollController _chatScrollController = ScrollController();
  final inputCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final checkInCtrl = TextEditingController();
  final checkOutCtrl = TextEditingController();
  String? sessionId;
  bool loading = false;
  late BookingService bookingService;

  // Search context tracking for multi-turn conversations
  String? lastSearchCity;
  String? lastSearchCheckIn;
  String? lastSearchCheckOut;
  bool isWaitingForCheckOut = false;

  // Destination tracking for hotel revalidation
  String? lastDestinationId;
  String? lastDestinationCode;
  String? lastToken;
  String? lastRecommendationId;
  String? lastCorrelationId;

  String? _pendingBookingQuery;
  bool? _awaitingTravelerCounts = false;
  HotelSortMode _hotelSortMode = HotelSortMode.defaultOrder;
  HotelSortMode _flightSortMode = HotelSortMode.defaultOrder;

  String get base {
    if (kIsWeb) return 'http://localhost:3000/api';
    return 'http://10.0.2.2:3000/api';
  }

  @override
  void initState() {
    super.initState();
    sessionId = Uuid().v4();
    bookingService = BookingService(baseUrl: base);
    _bot(
      'Hi — I can help you book flights or hotels. Tap Plan hotel or Plan flight to pick dates and traveler counts.',
    );
  }

  @override
  void dispose() {
    _chatScrollController.dispose();
    inputCtrl.dispose();
    cityCtrl.dispose();
    checkInCtrl.dispose();
    checkOutCtrl.dispose();
    super.dispose();
  }

  void _bot(String text) {
    setState(() => messages.insert(0, ChatMessage(text, fromUser: false)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: true);
    });
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_chatScrollController.hasClients) return;
    final target = _chatScrollController.position.minScrollExtent;
    if (animated) {
      _chatScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _chatScrollController.jumpTo(target);
    }
  }

  void _copyChatText(String text) {
    final copiedText = text.trim();
    if (copiedText.isEmpty) return;

    Clipboard.setData(ClipboardData(text: copiedText));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: const Text('Message copied'),
        leading: const Icon(Icons.check_circle, color: Colors.green),
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        messenger.hideCurrentMaterialBanner();
      }
    });
  }

  Widget _buildPlannerActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1e3c72),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: const Color(0xFF1e3c72).withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPlannerDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openTripPlanner({required TripPlannerType initialType}) async {
    final formKey = GlobalKey<FormState>();
    final cityCtrl = TextEditingController();
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    TripPlannerType plannerType = initialType;
    DateTimeRange? hotelRange;
    DateTime? flightDate;
    int adults = 2;
    int children = 0;

    try {
      final plannedMessage = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> pickHotelDates() async {
                final now = DateTime.now();
                final firstDate = DateTime(now.year, now.month, now.day);
                final initialRange = hotelRange ??
                    DateTimeRange(
                      start: firstDate.add(const Duration(days: 1)),
                      end: firstDate.add(const Duration(days: 2)),
                    );
                final range = await showDateRangePicker(
                  context: sheetContext,
                  firstDate: firstDate,
                  lastDate: firstDate.add(const Duration(days: 365)),
                  initialDateRange: initialRange,
                );
                if (range != null) {
                  setSheetState(() => hotelRange = range);
                }
              }

              Future<void> pickFlightDate() async {
                final now = DateTime.now();
                final firstDate = DateTime(now.year, now.month, now.day);
                final initialDate =
                    flightDate ?? firstDate.add(const Duration(days: 1));
                final selectedDate = await showDatePicker(
                  context: sheetContext,
                  firstDate: firstDate,
                  lastDate: firstDate.add(const Duration(days: 365)),
                  initialDate: initialDate,
                );
                if (selectedDate != null) {
                  setSheetState(() => flightDate = selectedDate);
                }
              }

              Widget buildPeopleSelector({
                required String label,
                required int value,
                required int min,
                required int max,
                required ValueChanged<int> onChanged,
              }) {
                return DropdownButtonFormField<int>(
                  value: value,
                  decoration: InputDecoration(
                    labelText: label,
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (var count = min; count <= max; count++)
                      DropdownMenuItem(
                        value: count,
                        child: Text(count.toString()),
                      ),
                  ],
                  onChanged: (selected) {
                    if (selected != null) {
                      onChanged(selected);
                    }
                  },
                );
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: 760,
                        maxHeight:
                            MediaQuery.of(sheetContext).size.height * 0.9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 24,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF0FF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Date-first booking',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF1e3c72),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Plan your trip',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Choose the stay or departure date first. We’ll keep the traveler count and booking details in sync.',
                                style: TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Hotel'),
                                    selected:
                                        plannerType == TripPlannerType.hotel,
                                    onSelected: (_) {
                                      setSheetState(() =>
                                          plannerType = TripPlannerType.hotel);
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Flight'),
                                    selected:
                                        plannerType == TripPlannerType.flight,
                                    onSelected: (_) {
                                      setSheetState(() =>
                                          plannerType = TripPlannerType.flight);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (plannerType == TripPlannerType.hotel) ...[
                                const Text(
                                  '1. Select stay dates',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1e3c72),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: pickHotelDates,
                                  icon: const Icon(Icons.date_range),
                                  label: const Text(
                                    'Choose check-in and check-out',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1e3c72),
                                    side: const BorderSide(
                                      color: Color(0xFFd7e0f4),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                if (hotelRange != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F7FD),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE1E7F4),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.event_available,
                                          color: Color(0xFF1e3c72),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Stay dates: ${_formatPlannerDate(hotelRange!.start)} to ${_formatPlannerDate(hotelRange!.end)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                const Text(
                                  '2. Tell us where you want to stay',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1e3c72),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: cityCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Destination city',
                                    filled: true,
                                    fillColor: Color(0xFFF9FBFF),
                                    border: OutlineInputBorder(),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Enter a city';
                                    }
                                    return null;
                                  },
                                ),
                              ] else ...[
                                const Text(
                                  '1. Choose where you are flying',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1e3c72),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: fromCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'From',
                                    filled: true,
                                    fillColor: Color(0xFFF9FBFF),
                                    border: OutlineInputBorder(),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Enter a departure location';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: toCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                    filled: true,
                                    fillColor: Color(0xFFF9FBFF),
                                    border: OutlineInputBorder(),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Enter a destination';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  '2. Select the departure date',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1e3c72),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: pickFlightDate,
                                  icon: const Icon(Icons.flight_takeoff),
                                  label: const Text('Choose departure date'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1e3c72),
                                    side: const BorderSide(
                                      color: Color(0xFFd7e0f4),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                if (flightDate != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F7FD),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE1E7F4),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.event_available,
                                          color: Color(0xFF1e3c72),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Departure date: ${_formatPlannerDate(flightDate!)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 16),
                              const Text(
                                '3. Add travelers',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1e3c72),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: buildPeopleSelector(
                                      label: 'Adults',
                                      value: adults,
                                      min: 1,
                                      max: 9,
                                      onChanged: (value) =>
                                          setSheetState(() => adults = value),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: buildPeopleSelector(
                                      label: 'Children',
                                      value: children,
                                      min: 0,
                                      max: 9,
                                      onChanged: (value) =>
                                          setSheetState(() => children = value),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (!formKey.currentState!.validate())
                                      return;

                                    if (plannerType == TripPlannerType.hotel) {
                                      if (hotelRange == null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Pick hotel dates before continuing.'),
                                          ),
                                        );
                                        return;
                                      }

                                      final city = cityCtrl.text.trim();
                                      final adultsLabel = adults == 1
                                          ? '1 adult'
                                          : '$adults adults';
                                      final childrenLabel = children == 1
                                          ? '1 child'
                                          : '$children children';
                                      Navigator.of(sheetContext).pop(
                                        'book a hotel in $city from ${_formatPlannerDate(hotelRange!.start)} to ${_formatPlannerDate(hotelRange!.end)} for $adultsLabel and $childrenLabel',
                                      );
                                      return;
                                    }

                                    if (flightDate == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Pick a departure date before continuing.'),
                                        ),
                                      );
                                      return;
                                    }

                                    final from = fromCtrl.text.trim();
                                    final to = toCtrl.text.trim();
                                    final adultsLabel = adults == 1
                                        ? '1 adult'
                                        : '$adults adults';
                                    final childrenLabel = children == 1
                                        ? '1 child'
                                        : '$children children';
                                    Navigator.of(sheetContext).pop(
                                      'book a flight from $from to $to on ${_formatPlannerDate(flightDate!)} for $adultsLabel and $childrenLabel',
                                    );
                                  },
                                  icon: const Icon(Icons.auto_awesome),
                                  label: Text(
                                    plannerType == TripPlannerType.hotel
                                        ? 'Search hotels with these dates'
                                        : 'Search flights with this date',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1e3c72),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (plannedMessage != null && plannedMessage.trim().isNotEmpty) {
        await _send(plannedMessage);
      }
    } finally {
      cityCtrl.dispose();
      fromCtrl.dispose();
      toCtrl.dispose();
    }
  }

  /// Handles the API response and converts technical errors into conversation
  void _handleApiResponse(Map<String, dynamic> data) {
    sessionId = data['sessionId'] ?? sessionId;

    // Persist hotel date context whenever backend provides it.
    final responseCheckIn = data['checkIn']?.toString().trim();
    final responseCheckOut = data['checkOut']?.toString().trim();
    if (responseCheckIn != null && responseCheckIn.isNotEmpty) {
      lastSearchCheckIn = responseCheckIn;
    }
    if (responseCheckOut != null && responseCheckOut.isNotEmpty) {
      lastSearchCheckOut = responseCheckOut;
    }

    // Update sessionId if returned
    if (data['sessionId'] != null) {
      sessionId = data['sessionId'];
    }

    // Handle API response with nested result structure
    // The API returns: { cards: { success: true, result: [...] } }
    if (data['cards'] != null && data['cards'] is Map) {
      final cardsData = data['cards'] as Map<String, dynamic>;

      // Check if it has result array (API format)
      if (cardsData['result'] != null && cardsData['result'] is List) {
        final results = cardsData['result'] as List;
        if (results.isNotEmpty) {
          final reply = data['reply'] ??
              'I found ${cardsData['count'] ?? results.length} options for you:';

          // Extract destinationId from first result if this is a hotel search
          if (results.isNotEmpty && results.first is Map) {
            final firstResult = results.first as Map;
            if (firstResult['destinationId'] != null) {
              lastDestinationId = firstResult['destinationId'].toString();
            }
            if (firstResult['destinationCode'] != null) {
              lastDestinationCode = firstResult['destinationCode'].toString();
            }
          }

          // Transform results into card format if needed
          final cards = results.map((flight) {
            if (flight is Map) {
              // Extract key info from flight object
              final mainFlight =
                  flight['flights'] != null ? flight['flights'][0] : null;

              if (mainFlight != null) {
                return {
                  'id': flight['fareSourceCode'] ??
                      'flight_${results.indexOf(flight)}',
                  'fareSourceCode': flight['fareSourceCode'],
                  'key_0': flight['coin'] ??
                      flight['showOurprice'] ??
                      flight['totalFare'],
                  'name':
                      '${mainFlight['airline']} ${mainFlight['flightCode']}${mainFlight['flightNumber']}',
                  'airline': mainFlight['airline'],
                  'airlineCode': mainFlight['flightCode'],
                  'flightNumber': mainFlight['flightNumber'],
                  'departureCode': mainFlight['departure'],
                  'arrivalCode': mainFlight['arrival'],
                  'departureLocation': mainFlight['departurelocation'],
                  'arrivalLocation': mainFlight['arrivallocation'],
                  'fareFamily': mainFlight['fareFamily'],
                  'price': flight['showOurprice'] ?? flight['totalFare'] ?? '0',
                  'baseFare': flight['baseFare'],
                  'totalFare': flight['totalFare'],
                  'taxes': flight['taxes'],
                  'taxBreakUp': flight['taxBreakUp'],
                  'stops': flight['stops'] ?? 0,
                  'departure': mainFlight['departureTime'],
                  'arrival': mainFlight['arrivalTime'],
                  'segments': flight['flights'],
                  'ticketingTime': flight['ticketingTime'],
                  'exchangeTime': flight['exchangeTime'],
                  'voidTime': flight['voidTime'],
                  'penaltyDetails': flight['penaltydetails'],
                  'rawFlight': flight,
                  // Preserve destination info for bookings
                  'destinationId': flight['destinationId'],
                  'destinationCode': flight['destinationCode'],
                  'token': flight['token'] ?? flight['result']?['token'],
                  'recommendationId': flight['recommendationId'] ??
                      flight['result']?['recommendationId'],
                  'checkIn': responseCheckIn ?? lastSearchCheckIn,
                  'checkOut': responseCheckOut ?? lastSearchCheckOut,
                };
              }

              return {
                ...flight,
                'checkIn':
                    flight['checkIn'] ?? responseCheckIn ?? lastSearchCheckIn,
                'checkOut': flight['checkOut'] ??
                    responseCheckOut ??
                    lastSearchCheckOut,
              };
            }
            return flight;
          }).toList();

          setState(
            () => messages.insert(
              0,
              ChatMessage(reply, fromUser: false, cards: cards),
            ),
          );
          return;
        }
      }
    }

    // Handle successful results with cards array (old format)
    if (data['cards'] != null &&
        data['cards'] is List &&
        data['cards'].isNotEmpty) {
      final cards = data['cards'] as List;
      final reply = data['reply'] ?? 'Here are your options:';

      // Extract destination and booking tokens from first hotel result
      if (cards.isNotEmpty && cards.first is Map) {
        final firstCard = cards.first as Map;
        if (firstCard['destinationId'] != null) {
          lastDestinationId = firstCard['destinationId'].toString();
        }
        if (firstCard['destinationCode'] != null) {
          lastDestinationCode = firstCard['destinationCode'].toString();
        }
        if (firstCard['token'] != null) {
          lastToken = firstCard['token'].toString();
        }
        final firstCardRecommendationId =
            firstCard['recommendationId']?.toString().trim();
        if (firstCardRecommendationId != null &&
            firstCardRecommendationId.isNotEmpty) {
          lastRecommendationId = firstCardRecommendationId;
        }
        final firstCardCorrelationId =
            firstCard['correlationId']?.toString().trim() ??
                firstCard['result']?['correlationId']?.toString().trim();
        if (firstCardCorrelationId != null &&
            firstCardCorrelationId.isNotEmpty) {
          lastCorrelationId = firstCardCorrelationId;
        }
      }

      final normalizedCards = cards.map((item) {
        if (item is Map) {
          final itemRecommendationId =
              item['recommendationId']?.toString().trim();
          final nestedRecommendationId =
              item['result']?['recommendationId']?.toString().trim();
          final itemCorrelationId =
              item['correlationId']?.toString().trim() ??
                  item['result']?['correlationId']?.toString().trim();
          return {
            ...item,
            'token':
                item['token'] ?? item['hotelToken'] ?? item['result']?['token'],
            'recommendationId': (itemRecommendationId != null &&
                    itemRecommendationId.isNotEmpty)
                ? itemRecommendationId
                : (nestedRecommendationId != null &&
                        nestedRecommendationId.isNotEmpty)
                    ? nestedRecommendationId
                    : lastRecommendationId,
            'correlationId': itemCorrelationId ?? lastCorrelationId,
            // Preserve search context for booking
            'checkIn': item['checkIn'] ?? responseCheckIn ?? lastSearchCheckIn,
            'checkOut':
                item['checkOut'] ?? responseCheckOut ?? lastSearchCheckOut,
            'rooms': item['rooms'] ??
                [
                  {
                    'childAges': [],
                    'children': 0,
                    'adults': 2,
                  }
                ],
          };
        }
        return item;
      }).toList();

      setState(
        () => messages.insert(
          0,
          ChatMessage(reply, fromUser: false, cards: normalizedCards),
        ),
      );
      return;
    }

    // Handle plain text replies
    String botReply = data['reply'] ?? "I couldn't find any results for that.";
    _bot(botReply);
  }

  String? _getImageUrlFromLinks(dynamic links) {
    if (links == null) return null;
    if (links is String) return links;

    if (links is Map) {
      // Prefer the bigger image sizes when available.
      const preferred = ['1000px', '750px', '350px', '200px', '70px'];
      for (final key in preferred) {
        final value = links[key];
        if (value is String) return value;
        if (value is Map && value['href'] is String) {
          return value['href'] as String;
        }
      }

      // If the map has direct href or url keys.
      if (links['href'] is String) return links['href'] as String;
      if (links['url'] is String) return links['url'] as String;
    }

    if (links is List) {
      // Prefer largest by hints or first non-null url/href.
      for (final item in links) {
        if (item is Map) {
          if (item['href'] is String) return item['href'] as String;
          if (item['url'] is String) return item['url'] as String;
        }
      }
    }

    return null;
  }

  String? _resolveImageUrl(dynamic image) {
    if (image == null) return null;
    if (image is String) return image;
    if (image is Map) {
      if (image['url'] is String) return image['url'] as String;
      if (image['href'] is String) return image['href'] as String;
      if (image['heroImage'] is String) return image['heroImage'] as String;

      final links = image['links'];
      final url = _getImageUrlFromLinks(links);
      if (url != null) return url;

      // Support images that are nested like { 'size': ..., 'links': ... }
      if (image['link'] != null) {
        final nested = _resolveImageUrl(image['link']);
        if (nested != null) return nested;
      }
    }

    return null;
  }

  String _proxyImageUrl(String imageUrl) {
    final encoded = Uri.encodeComponent(imageUrl);
    return '$base/image-proxy?url=$encoded';
  }

  // Backward-compatible alias used in case previous hot-reload closures still reference
  // the old method name from prior edits.
  String? _extractImageUrl(dynamic image) => _resolveImageUrl(image);

  bool _isBookingIntentForTravelerPrompt(String message) {
    // Booking lookup/cancel intents should go straight to backend without traveler prompts.
    if (RegExp(r'\b(b_\d+)\b', caseSensitive: false).hasMatch(message)) {
      return false;
    }

    if (RegExp(
      r'\b(booking\s*(info|information|details|status)|show\s+booking|cancel\s+booking|reservation\s*(info|details|status))\b',
      caseSensitive: false,
    ).hasMatch(message)) {
      return false;
    }

    return RegExp(
      r'\b(book|flight|fly|hotel|stay|room|accommodation)\b',
      caseSensitive: false,
    ).hasMatch(message);
  }

  Map<String, int>? _extractTravelerCounts(String message) {
    final adultsMatch = RegExp(
      r'(\d+)\s*(adult|adults|passenger|passengers|guest|guests|person|people)',
      caseSensitive: false,
    ).firstMatch(message);
    final childrenMatch = RegExp(
      r'(\d+)\s*(child|children|kid|kids)',
      caseSensitive: false,
    ).firstMatch(message);

    if (adultsMatch == null && childrenMatch == null) return null;

    final adults = int.tryParse(adultsMatch?.group(1) ?? '') ?? 2;
    final children = int.tryParse(childrenMatch?.group(1) ?? '') ?? 0;
    return {'adults': adults, 'children': children};
  }

  String? _buildIsoDate(int year, int month, int day) {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }

    final y = date.year.toString().padLeft(4, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  String? _normalizeNaturalDate(String raw, {required int defaultYear}) {
    final numericMatch = RegExp(
      r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$',
    ).firstMatch(raw);
    if (numericMatch != null) {
      final first = int.tryParse(numericMatch.group(1) ?? '');
      final second = int.tryParse(numericMatch.group(2) ?? '');
      final year = int.tryParse(numericMatch.group(3) ?? '');
      if (first == null || second == null || year == null) return null;

      final ddMm = _buildIsoDate(year, second, first);
      final mmDd = _buildIsoDate(year, first, second);

      if (first > 12) return ddMm;
      if (second > 12) return mmDd;
      return ddMm ?? mmDd;
    }

    final monthFirstMatch = RegExp(
      r'^\s*([a-zA-Z]+)\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?\s*$',
    ).firstMatch(raw);
    if (monthFirstMatch != null) {
      final monthToken = (monthFirstMatch.group(1) ?? '').toLowerCase();
      final day = int.tryParse(monthFirstMatch.group(2) ?? '');
      final year = int.tryParse(monthFirstMatch.group(3) ?? '') ?? defaultYear;
      if (day == null) return null;

      const monthMap = {
        'jan': 1,
        'january': 1,
        'feb': 2,
        'february': 2,
        'mar': 3,
        'march': 3,
        'apr': 4,
        'april': 4,
        'may': 5,
        'jun': 6,
        'june': 6,
        'jul': 7,
        'july': 7,
        'aug': 8,
        'august': 8,
        'sep': 9,
        'sept': 9,
        'september': 9,
        'oct': 10,
        'october': 10,
        'nov': 11,
        'november': 11,
        'dec': 12,
        'december': 12,
      };

      final month = monthMap[monthToken];
      if (month == null) return null;
      return _buildIsoDate(year, month, day);
    }

    final dayFirstMatch = RegExp(
      r'^\s*(\d{1,2})(?:st|nd|rd|th)?\s+([a-zA-Z]+)(?:\s+(\d{4}))?\s*$',
    ).firstMatch(raw);
    if (dayFirstMatch == null) return null;

    final day = int.tryParse(dayFirstMatch.group(1) ?? '');
    final monthToken = (dayFirstMatch.group(2) ?? '').toLowerCase();
    final year = int.tryParse(dayFirstMatch.group(3) ?? '') ?? defaultYear;
    if (day == null) return null;

    const monthMap = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };

    final month = monthMap[monthToken];
    if (month == null) return null;
    return _buildIsoDate(year, month, day);
  }

  String _normalizeNaturalDatesInMessage(String message) {
    final nowYear = DateTime.now().year;
    final naturalDateRegex = RegExp(
      r'\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{4}|\d{1,2}(?:st|nd|rd|th)?\s+[a-zA-Z]+(?:\s+\d{4})?|[a-zA-Z]+\s+\d{1,2}(?:st|nd|rd|th)?(?:\s+\d{4})?)\b',
      caseSensitive: false,
    );

    return message.replaceAllMapped(naturalDateRegex, (m) {
      final normalized =
          _normalizeNaturalDate(m.group(0)!, defaultYear: nowYear);
      return normalized ?? m.group(0)!;
    });
  }

  /// Check if string is a date in format YYYY-MM-DD
  bool _isSupportedDateFormat(String text) {
    return _normalizeNaturalDate(text.trim(),
            defaultYear: DateTime.now().year) !=
        null;
  }

  /// Extract search parameters (city, check-in, check-out) from user message
  Map<String, String?> _extractSearchParameters(String message) {
    final normalizedMessage = _normalizeNaturalDatesInMessage(message);
    final lowerMsg = normalizedMessage.toLowerCase();
    String? city;
    String? checkIn;
    String? checkOut;

    // Look for date patterns in supported formats and normalize to YYYY-MM-DD.
    final dateRegex = RegExp(
      r'\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{4}|\d{1,2}(?:st|nd|rd|th)?\s+[a-zA-Z]+(?:\s+\d{4})?|[a-zA-Z]+\s+\d{1,2}(?:st|nd|rd|th)?(?:\s+\d{4})?)\b',
      caseSensitive: false,
    );
    final dates = dateRegex.allMatches(normalizedMessage);

    if (dates.isNotEmpty) {
      checkIn = _normalizeNaturalDate(
        dates.first.group(0)!,
        defaultYear: DateTime.now().year,
      );
      if (dates.length > 1) {
        checkOut = _normalizeNaturalDate(
          dates.elementAt(1).group(0)!,
          defaultYear: DateTime.now().year,
        );
      }
    }

    // Try to extract city (common patterns)
    if (lowerMsg.contains('hotel in ')) {
      final idx = lowerMsg.indexOf('hotel in ') + 'hotel in '.length;
      final afterIn = normalizedMessage.substring(idx);
      final beforeFrom = afterIn.split(' from').first.trim();
      final beforeDate = beforeFrom.split(' on').first.trim();
      if (beforeDate.isNotEmpty) {
        city = beforeDate;
      }
    } else if (lowerMsg.contains(' in ')) {
      final idx = lowerMsg.lastIndexOf(' in ') + ' in '.length;
      final afterIn = normalizedMessage.substring(idx);
      final beforeFrom = afterIn.split(' from').first.trim();
      final beforeDate = beforeFrom.split(' on').first.trim();
      if (beforeDate.isNotEmpty && !_isSupportedDateFormat(beforeDate)) {
        city = beforeDate;
      }
    }

    return {'city': city, 'checkIn': checkIn, 'checkOut': checkOut};
  }

  /// Try to format incomplete hotel search as complete query
  String? _tryFormatAsHotelSearch(String userMessage) {
    final params = _extractSearchParameters(userMessage);

    // If this looks like just a checkout date and we have previous context
    final normalizedSingleDate = _normalizeNaturalDate(
      userMessage.trim(),
      defaultYear: DateTime.now().year,
    );

    if (normalizedSingleDate != null &&
        lastSearchCity != null &&
        lastSearchCheckIn != null) {
      final checkOut = normalizedSingleDate;
      lastSearchCheckOut = checkOut;
      isWaitingForCheckOut = false;
      return 'Hotel in $lastSearchCity from $lastSearchCheckIn to $checkOut';
    }

    // Extract new search parameters
    if (params['city'] != null && params['checkIn'] != null) {
      lastSearchCity = params['city'];
      lastSearchCheckIn = params['checkIn'];

      // If we have checkout, it's complete
      if (params['checkOut'] != null) {
        lastSearchCheckOut = params['checkOut'];
        isWaitingForCheckOut = false;
        return 'Hotel in ${params['city']} from ${params['checkIn']} to ${params['checkOut']}';
      } else {
        // We need checkout date
        isWaitingForCheckOut = true;
        return null; // Let the backend ask for it
      }
    }

    isWaitingForCheckOut = false;
    return null; // Can't format, send as-is
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final normalizedText = _normalizeNaturalDatesInMessage(trimmed);

    if ((_awaitingTravelerCounts == true) && _pendingBookingQuery != null) {
      final travelerCounts = _extractTravelerCounts(normalizedText);

      setState(() => messages.insert(0, ChatMessage(trimmed, fromUser: true)));
      inputCtrl.clear();

      if (travelerCounts == null) {
        _bot('Please share traveler counts like "2 adults and 1 child".');
        return;
      }

      final combinedQuery =
          '${_pendingBookingQuery!} for ${travelerCounts['adults']} adults and ${travelerCounts['children']} children';
      _pendingBookingQuery = null;
      _awaitingTravelerCounts = false;
      await _sendToBackend(combinedQuery);
      return;
    }

    final travelerCounts = _extractTravelerCounts(normalizedText);
    if (_isBookingIntentForTravelerPrompt(normalizedText) &&
        travelerCounts == null) {
      _pendingBookingQuery = normalizedText;
      _awaitingTravelerCounts = true;
      setState(() => messages.insert(0, ChatMessage(trimmed, fromUser: true)));
      inputCtrl.clear();
      _bot('How many adults and children should I include for this booking?');
      return;
    }

    setState(() {
      messages.insert(0, ChatMessage(trimmed, fromUser: true));
    });
    inputCtrl.clear();
    await _sendToBackend(normalizedText);
  }

  Future<void> _sendToBackend(String messageText) async {
    String userDisplayMessage = messageText;

    final formattedMessage = _tryFormatAsHotelSearch(messageText);
    if (formattedMessage != null && formattedMessage != messageText) {
      userDisplayMessage = formattedMessage;
    }

    setState(() => loading = true);

    try {
      final r = await http.post(
        Uri.parse('$base/chat'),
        body: json.encode({
          'sessionId': sessionId,
          'message': userDisplayMessage,
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (r.statusCode >= 200 && r.statusCode < 300) {
        final data = json.decode(r.body);
        _handleApiResponse(data);
      } else {
        _bot("Server error: ${r.statusCode}");
      }
    } catch (e) {
      _bot("Network error. Please check your connection.");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _selectCard(dynamic it) async {
    final name = it['name'] ?? 'Selected item';
    final price = it['ourprice'] ?? it['price'] ?? 'N/A';
    final isLikelyHotel = _isHotelCard(it);

    final defaultRoomsConfig = [
      {
        'childAges': [],
        'children': 0,
        'adults': 2,
      }
    ];

    // Ensure hotel object has destinationId for booking
    if (it is Map && it['destinationId'] == null && lastDestinationId != null) {
      it['destinationId'] = lastDestinationId;
    }
    if (it is Map &&
        it['destinationCode'] == null &&
        lastDestinationCode != null) {
      it['destinationCode'] = lastDestinationCode;
    }

    // Ensure we have booking token and recommendationId for revalidate
    if (it is Map && it['token'] == null && lastToken != null) {
      it['token'] = lastToken;
    }
    final itemRecommendationId =
        it is Map ? it['recommendationId']?.toString().trim() : null;
    final itemNestedRecommendationId = it is Map && it['result'] is Map
        ? (it['result'] as Map)['recommendationId']?.toString().trim()
        : null;
    if (it is Map &&
        (itemRecommendationId == null || itemRecommendationId.isEmpty) &&
        lastRecommendationId != null) {
      it['recommendationId'] = lastRecommendationId;
    } else if (it is Map &&
        (itemRecommendationId == null || itemRecommendationId.isEmpty) &&
        itemNestedRecommendationId != null &&
        itemNestedRecommendationId.isNotEmpty) {
      it['recommendationId'] = itemNestedRecommendationId;
    }
    if (it is Map &&
        (it['checkIn'] == null || it['checkIn'].toString().isEmpty) &&
        lastSearchCheckIn != null) {
      it['checkIn'] = lastSearchCheckIn;
    }
    if (it is Map &&
        (it['checkOut'] == null || it['checkOut'].toString().isEmpty) &&
        lastSearchCheckOut != null) {
      it['checkOut'] = lastSearchCheckOut;
    }
    if (it is Map && it['rooms'] == null) {
      it['rooms'] = defaultRoomsConfig;
    }
    if (it is Map &&
        (it['correlationId'] == null || it['correlationId'].toString().isEmpty) &&
        lastCorrelationId != null) {
      it['correlationId'] = lastCorrelationId;
    }

    setState(
      () => messages.insert(0, ChatMessage('$name — \$$price', fromUser: true)),
    );

    // Hotel booking is completed through the payment dialog flow.
    if (isLikelyHotel) {
      _showBookingConfirmation(it);
      return;
    }

    if (_isFlightCard(it)) {
      await _handleFlightSelectionWithPayment(it);
      return;
    }

    // Still send to backend
    setState(() => loading = true);

    try {
      final r = await http.post(
        Uri.parse('$base/chat'),
        body: json.encode({
          'sessionId': sessionId,
          'message': 'select:${it['id']}',
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (r.statusCode >= 200 && r.statusCode < 300) {
        final data = json.decode(r.body);
        _handleApiResponse(data);
      } else {
        _bot('Server error: ${r.statusCode}');
      }
    } catch (e) {
      _bot('Network error');
    } finally {
      setState(() => loading = false);
    }
  }

  String? _extractPaymentUrl(dynamic data) {
    if (data == null) return null;
    if (data is String && data.startsWith('http')) return data;
    if (data is! Map) return null;

    const candidates = [
      'paymentUrl',
      'paymentURL',
      'payment_url',
      'url',
      'checkoutUrl',
      'checkout_url',
      'redirectUrl',
      'redirect_url',
      'link',
      'paymentLink',
      'payment_link',
    ];

    for (final key in candidates) {
      final v = data[key];
      if (v is String && v.startsWith('http')) return v;
    }

    final nestedCandidates = [
      data['result'],
      data['data'],
      data['body'],
      data['response'],
      data['payload'],
      data['result']?['response'],
      data['result']?['data'],
      data['result']?['body'],
    ];
    for (final nested in nestedCandidates) {
      final nestedUrl = _extractPaymentUrl(nested);
      if (nestedUrl != null) return nestedUrl;
    }

    return null;
  }

  num _extractFlightKey0(dynamic it) {
    final candidates = <dynamic>[
      it['key_0'],
      it['key0'],
      it['coin'],
      it['showOurprice'],
      it['totalFare'],
      it['rawFlight']?['key_0'],
      it['rawFlight']?['key0'],
      it['rawFlight']?['coin'],
      it['rawFlight']?['showOurprice'],
      it['rawFlight']?['totalFare'],
      it['rawFlight']?['result']?['key_0'],
      it['rawFlight']?['result']?['coin'],
      it['rawFlight']?['pricing']?['showOurprice'],
      it['rawFlight']?['pricing']?['ourprice'],
    ];

    for (final value in candidates) {
      final parsed = num.tryParse('${value ?? ''}');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return 0;
  }

  Future<bool> _showFlightRevalidatedDialog(
      dynamic revalidate, dynamic selectedFlight) async {
    final root = (revalidate is Map) ? revalidate : <String, dynamic>{};
    final result =
        (root['result'] is Map) ? root['result'] as Map : <String, dynamic>{};
    final pricing = (result['pricing'] is Map)
        ? result['pricing'] as Map
        : <String, dynamic>{};
    final ptcInfo =
        (result['ptcInfo'] is List) ? result['ptcInfo'] as List : <dynamic>[];
    final bookingRequired = (result['bookingRequired'] is List)
        ? result['bookingRequired'] as List
        : <dynamic>[];

    final totalFare = pricing['totalFare'] ?? result['coin'] ?? 'N/A';
    final taxes = pricing['taxes'] ?? 'N/A';
    final ourPrice = pricing['showOurprice'] ??
        pricing['ourprice'] ??
        result['coin'] ??
        'N/A';

    final firstPax = (ptcInfo.isNotEmpty && ptcInfo.first is Map)
        ? ptcInfo.first as Map
        : <String, dynamic>{};
    final baggageInfo = (firstPax['baggageInfo'] is List)
        ? firstPax['baggageInfo'] as List
        : <dynamic>[];
    final cabinBaggage = (firstPax['cabinBaggage'] is List)
        ? firstPax['cabinBaggage'] as List
        : <dynamic>[];
    final penalties = (firstPax['penaltiesInfo'] is List)
        ? firstPax['penaltiesInfo'] as List
        : <dynamic>[];

    final airline =
        (selectedFlight['airline'] ?? selectedFlight['name'] ?? 'Flight')
            .toString();
    final route =
        '${selectedFlight['departureCode'] ?? '---'} → ${selectedFlight['arrivalCode'] ?? '---'}';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade700, Colors.indigo.shade500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Fare Revalidated',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$airline • $route',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: _flightInfoChip(
                                          'Final Fare', '\$$ourPrice',
                                          backgroundColor: Colors.green.shade50,
                                          textColor: Colors.green.shade800)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: _flightInfoChip(
                                          'Base/Total', '\$$totalFare',
                                          backgroundColor:
                                              Colors.grey.shade100)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: _flightInfoChip(
                                          'Taxes', '\$$taxes',
                                          backgroundColor:
                                              Colors.orange.shade50,
                                          textColor: Colors.orange.shade800)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _flightInfoChip('Fare Type',
                                      '${result['fairtype'] ?? 'N/A'}',
                                      backgroundColor: Colors.indigo.shade50,
                                      textColor: Colors.indigo.shade700),
                                  _flightInfoChip('Refundable',
                                      '${result['isRefundable'] ?? 'N/A'}',
                                      backgroundColor: Colors.blue.shade50,
                                      textColor: Colors.blue.shade700),
                                  _flightInfoChip('Price Changed',
                                      '${result['pricechange'] == true ? 'Yes' : 'No'}',
                                      backgroundColor: Colors.purple.shade50,
                                      textColor: Colors.purple.shade700),
                                  _flightInfoChip('Itinerary Changed',
                                      '${result['iternarychange'] == true ? 'Yes' : 'No'}',
                                      backgroundColor: Colors.pink.shade50,
                                      textColor: Colors.pink.shade700),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _sectionTitle('Baggage & cabin allowance'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _detailRow(
                                  'Checked baggage',
                                  baggageInfo.isEmpty
                                      ? 'N/A'
                                      : baggageInfo.join(' • ')),
                              _detailRow(
                                  'Cabin baggage',
                                  cabinBaggage.isEmpty
                                      ? 'N/A'
                                      : cabinBaggage.join(' • ')),
                              _detailRow('Ticket type',
                                  '${result['ticketType'] ?? 'N/A'}'),
                              _detailRow('Void time',
                                  '${result['voidtime'] ?? 'N/A'} mins'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _sectionTitle('Penalty details'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: penalties.isEmpty
                              ? Text('No penalties data available',
                                  style: TextStyle(color: Colors.grey[700]))
                              : Column(
                                  children: penalties.map<Widget>((p) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${p['penaltyType'] ?? 'Penalty'}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                            ),
                                            Text(
                                              '${p['allowed'] == true ? 'Allowed' : 'Not allowed'} • ${p['amount'] ?? 'N/A'} ${p['currencyCode'] ?? ''}',
                                              style: TextStyle(
                                                  color: Colors.grey[800],
                                                  fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                        const SizedBox(height: 14),
                        _sectionTitle('Traveler details required'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: bookingRequired
                              .map<Widget>((f) => Chip(
                                    label: Text(
                                      f.toString().replaceAll('_', ' '),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    backgroundColor: Colors.indigo.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Continue to Payment'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _handleFlightSelectionWithPayment(dynamic it) async {
    final fareSourceCode = (it['fareSourceCode'] ?? it['id'] ?? '').toString();
    final key0 = _extractFlightKey0(it);

    if (fareSourceCode.isEmpty || key0 <= 0) {
      _bot(
          'Unable to process this flight selection. Please select another option.');
      return;
    }

    setState(() => loading = true);
    try {
      final revalidate = await bookingService.revalidateFlight(
        fareSourceCode: fareSourceCode,
        key0: key0,
      );

      if (revalidate is! Map || revalidate['success'] != true) {
        _bot(
            'Flight revalidation failed. Please try a different flight option.');
        return;
      }

      setState(() => loading = false);
      final proceedToPayment =
          await _showFlightRevalidatedDialog(revalidate, it);
      if (!proceedToPayment) {
        _bot(
            'Flight selection cancelled. You can choose another option anytime.');
        return;
      }
      setState(() => loading = true);

      final payment = await bookingService.getFlightPaymentUrl(
        fareSourceCode: fareSourceCode,
        key0: key0,
        revalidateResult: revalidate['result'] ?? revalidate,
        selectedFlight: it['rawFlight'] ?? it,
        origin: (it['departureCode'] ?? '').toString(),
        destination: (it['arrivalCode'] ?? '').toString(),
        departureDate:
            _formatDateTime(it['departure']?.toString()).split(' ').first,
      );

      final paymentUrl = _extractPaymentUrl(payment);
      if (paymentUrl == null) {
        _bot(
            'Flight revalidated, but payment URL is unavailable right now. Please try again in a moment.');
        return;
      }

      final url = Uri.parse(paymentUrl);
      if (!await canLaunchUrl(url)) {
        _bot('Could not open payment URL for this flight.');
        return;
      }

      await launchUrl(
        url,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );

      final bookingId = await bookingService.createBookingRecord(
        name: 'Flight Traveler',
        type: 'flight',
        itemId: fareSourceCode,
        details:
            'Route: ${it['departureCode'] ?? ''} -> ${it['arrivalCode'] ?? ''}, Date: ${it['departure'] ?? ''}',
      );

      _bot(
          'Flight payment initiated. Would you like to continue with any other booking?');
    } catch (e) {
      _bot(
          'Unable to complete flight payment flow right now. Please try again.');
    } finally {
      setState(() => loading = false);
    }
  }

  /// Show booking confirmation dialog with room selection and payment
  void _showBookingConfirmation(dynamic hotel) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Booking',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return BookingConfirmationDialog(
          hotel: hotel,
          bookingService: bookingService,
          onCancel: () {
            _bot('Would you like to book a flight or a hotel?');
          },
          onBookingConfirmed: (bookingId) {
            _bot(
                'Payment initiated. Would you like to continue with any other booking?');
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _searchHotels() async {
    final city = cityCtrl.text.trim();
    final checkIn = checkInCtrl.text.trim();
    final checkOut = checkOutCtrl.text.trim();

    if (city.isEmpty || checkIn.isEmpty || checkOut.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final defaultRoomsConfig = [
        {
          'childAges': [],
          'children': 0,
          'adults': 2,
        }
      ];

      // Resolve destination for search-hotels payload
      final destResp =
          await bookingService.searchHotelDestinations(query: city);
      final destinations = (destResp is Map)
          ? (destResp['result'] is List
              ? destResp['result'] as List
              : <dynamic>[])
          : <dynamic>[];

      if (destinations.isEmpty || destinations.first is! Map) {
        _bot('No destination found for "$city". Please try another city.');
        return;
      }

      final destination = destinations.first as Map;
      final destinationId = destination['id']?.toString() ?? '';
      final lat =
          (destination['coordinates']?['lat'] as num?)?.toDouble() ?? 0.0;
      final long =
          (destination['coordinates']?['long'] as num?)?.toDouble() ?? 0.0;

      if (destinationId.isEmpty) {
        _bot('Destination lookup failed. Please try again.');
        return;
      }

      final normalizedCheckIn = _normalizeNaturalDate(
        checkIn,
        defaultYear: DateTime.now().year,
      );
      final normalizedCheckOut = _normalizeNaturalDate(
        checkOut,
        defaultYear: DateTime.now().year,
      );

      if (normalizedCheckIn == null || normalizedCheckOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please use a supported date format like YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, June 2, or 2nd June.',
            ),
          ),
        );
        return;
      }

      // Step 1: call mcp/hotel/search-hotels
      final hotelsResp = await bookingService.searchHotels(
        destinationId: destinationId,
        checkIn: normalizedCheckIn,
        checkOut: normalizedCheckOut,
        rooms: defaultRoomsConfig,
        lat: lat,
        long: long,
      );

      final resultMap = hotelsResp is Map
          ? (hotelsResp['result'] is Map
              ? hotelsResp['result'] as Map
              : hotelsResp)
          : <String, dynamic>{};
      final hotels = resultMap['result'] is List
          ? resultMap['result'] as List
          : (resultMap['hotels'] is List
              ? resultMap['hotels'] as List
              : <dynamic>[]);

      if (hotels.isEmpty) {
        _bot('No hotels found for the selected dates.');
        return;
      }

      final token = resultMap['token']?.toString();
      final correlationId = resultMap['correlationId']?.toString();

      if (token != null && token.isNotEmpty) {
        lastToken = token;
      }
      if (correlationId != null && correlationId.isNotEmpty) {
        lastCorrelationId = correlationId;
      }
      lastDestinationId = destinationId;
      lastSearchCity = city;
      lastSearchCheckIn = normalizedCheckIn;
      lastSearchCheckOut = normalizedCheckOut;

      final normalizedCards = hotels.map((h) {
        if (h is! Map) return h;
        final recommendationId = h['recommendationId']?.toString().trim();
        if (recommendationId != null && recommendationId.isNotEmpty) {
          lastRecommendationId = recommendationId;
        }

        final itemCorrelationId = h['correlationId']?.toString().trim() ??
            h['result']?['correlationId']?.toString().trim() ??
            h['hotel']?['correlationId']?.toString().trim();
        if (itemCorrelationId != null && itemCorrelationId.isNotEmpty) {
          lastCorrelationId = itemCorrelationId;
        }

        final itemToken = h['token']?.toString().trim() ??
            h['hotelToken']?.toString().trim() ??
            h['result']?['token']?.toString().trim() ??
            token;
        if (itemToken != null && itemToken.isNotEmpty) {
          lastToken = itemToken;
        }

        return {
          ...h,
          'token': itemToken,
          'recommendationId': recommendationId ?? lastRecommendationId,
          'destinationId': h['destinationId'] ?? destinationId,
          'checkIn': normalizedCheckIn,
          'checkOut': normalizedCheckOut,
          'rooms': h['rooms'] ?? defaultRoomsConfig,
          'correlationId': itemCorrelationId ?? correlationId,
        };
      }).toList();

      setState(() {
        messages.insert(
          0,
          ChatMessage(
            'I found ${normalizedCards.length} hotels for your trip. Select a hotel to continue.',
            fromUser: false,
            cards: normalizedCards,
          ),
        );
      });
    } catch (e) {
      _bot('Hotel search failed: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // --- UI BUILDING METHODS ---

  Widget _chatTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1e3c72),
            Color(0xFF2a5298),
            Color(0xFF3d5a80),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background SVG image with opacity
          Positioned.fill(
            child: Opacity(
              opacity: 0.12,
              child: Image.asset(
                'assets/images/FlightNHotel.webp',
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Chat content
          Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _chatScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  thickness: 10,
                  radius: const Radius.circular(10),
                  child: ListView.builder(
                    controller: _chatScrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      final m = messages[i];
                      return (m.cards != null && m.cards!.isNotEmpty)
                          ? _buildCardMessage(m)
                          : _buildTextMessage(m);
                    },
                  ),
                ),
              ),
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextMessage(ChatMessage m) {
    final messageText = m.text ?? '';

    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: m.fromUser
              ? LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [Color(0xFFf5f5f5), Color(0xFFfafafa)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (messageText.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 18,
                  onPressed: () => _copyChatText(messageText),
                  icon: Icon(
                    Icons.copy,
                    size: 18,
                    color: m.fromUser ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ),
            SelectableText(
              messageText,
              style: TextStyle(
                fontSize: 15,
                color: m.fromUser ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardMessage(ChatMessage m) {
    final screenWidth = MediaQuery.of(context).size.width;
    final preferredWidth = screenWidth * 0.86;
    final maxCardWidth = preferredWidth > 780 ? 780.0 : preferredWidth;
    final cards = m.cards ?? [];
    final hotelCards = cards.where(_isHotelCard).toList();
    final flightCards = cards.where(_isFlightCard).toList();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxCardWidth),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.text != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(m.text!,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            if (hotelCards.isNotEmpty) _buildHotelTabs(hotelCards),
            if (flightCards.isNotEmpty) _buildFlightTabs(flightCards),
          ],
        ),
      ),
    );
  }

  List<List<dynamic>> _chunkCards(List<dynamic> cards, int chunkSize) {
    if (cards.isEmpty) return [];
    final chunks = <List<dynamic>>[];
    for (var index = 0; index < cards.length; index += chunkSize) {
      final end =
          (index + chunkSize < cards.length) ? index + chunkSize : cards.length;
      chunks.add(cards.sublist(index, end));
    }
    return chunks;
  }

  double? _priceForHotelCard(dynamic hotelCard) {
    if (hotelCard is! Map) return null;

    final candidates = [
      hotelCard['ourprice'],
      hotelCard['price'],
      hotelCard['displayedPrice'],
      hotelCard['nightlyPrice'],
      hotelCard['totalPrice'],
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final parsed = double.tryParse(candidate.toString().replaceAll(',', ''));
      if (parsed != null) return parsed;
    }

    return null;
  }

  List<dynamic> _sortHotelCardsByPrice(List<dynamic> hotelCards) {
    if (hotelCards.length < 2) return List<dynamic>.from(hotelCards);

    final sortedCards = List<dynamic>.from(hotelCards);
    if (_hotelSortMode == HotelSortMode.defaultOrder) return sortedCards;

    sortedCards.sort((left, right) {
      final leftPrice = _priceForHotelCard(left);
      final rightPrice = _priceForHotelCard(right);

      if (leftPrice == null && rightPrice == null) return 0;
      if (leftPrice == null) return 1;
      if (rightPrice == null) return -1;

      return _hotelSortMode == HotelSortMode.priceLowToHigh
          ? leftPrice.compareTo(rightPrice)
          : rightPrice.compareTo(leftPrice);
    });

    return sortedCards;
  }

  Widget _buildPriceSortControls({
    required HotelSortMode selectedMode,
    required ValueChanged<HotelSortMode> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Default'),
          selected: selectedMode == HotelSortMode.defaultOrder,
          onSelected: (_) => onChanged(HotelSortMode.defaultOrder),
        ),
        ChoiceChip(
          label: const Text('Price: Low to High'),
          selected: selectedMode == HotelSortMode.priceLowToHigh,
          onSelected: (_) => onChanged(HotelSortMode.priceLowToHigh),
        ),
        ChoiceChip(
          label: const Text('Price: High to Low'),
          selected: selectedMode == HotelSortMode.priceHighToLow,
          onSelected: (_) => onChanged(HotelSortMode.priceHighToLow),
        ),
      ],
    );
  }

  Widget _buildHotelTabs(List<dynamic> hotelCards) {
    final sortedCards = _sortHotelCardsByPrice(hotelCards);
    final groups = _chunkCards(sortedCards, 3);
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortControls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sort hotels by price',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        _buildPriceSortControls(
          selectedMode: _hotelSortMode,
          onChanged: (mode) {
            setState(() => _hotelSortMode = mode);
          },
        ),
      ],
    );

    if (groups.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sortControls,
          const SizedBox(height: 12),
          ...groups.first.map((it) => _buildHotelOptionCard(it)).toList(),
        ],
      );
    }

    return DefaultTabController(
      length: groups.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sortControls,
          const SizedBox(height: 12),
          TabBar(
            isScrollable: true,
            indicatorColor: Colors.indigo,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey[700],
            tabs: [
              for (var index = 0; index < groups.length; index++)
                Tab(
                    text:
                        '${index * 3 + 1}-${index * 3 + groups[index].length}'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 980,
            child: TabBarView(
              children: [
                for (final group in groups)
                  SingleChildScrollView(
                    child: Column(
                      children:
                          group.map((it) => _buildHotelOptionCard(it)).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isFlightCard(dynamic it) {
    return it is Map &&
        (it['fareSourceCode'] != null ||
            it['segments'] != null ||
            it['departureCode'] != null);
  }

  bool _isHotelCard(dynamic it) {
    if (it is! Map) return false;
    if (_isFlightCard(it)) return false;

    // Hotel cards can come in slightly different shapes depending on source.
    return it['hotelId'] != null ||
        it['id'] != null ||
        it['token'] != null ||
        it['recommendationId'] != null ||
        it['starRating'] != null ||
        it['heroImage'] != null ||
        it['mainamenity'] != null;
  }

  String? _flightLogoUrl(dynamic it) {
    if (it is! Map) return null;
    final airlineCode = (it['airlineCode'] ??
            (it['segments'] is List && (it['segments'] as List).isNotEmpty
                ? it['segments'][0]['flightCode']
                : null))
        ?.toString()
        .toUpperCase();

    if (airlineCode == null || airlineCode.length < 2) return null;
    return 'https://images.kiwi.com/airlines/64/$airlineCode.png';
  }

  String? _flightLogoProxyUrl(dynamic it) {
    final logoUrl = _flightLogoUrl(it);
    if (logoUrl == null) return null;
    return _proxyImageUrl(logoUrl);
  }

  String _formatTimeOnly(String? iso) {
    if (iso == null || iso.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDuration(String? startIso, String? endIso) {
    final start = DateTime.tryParse(startIso ?? '');
    final end = DateTime.tryParse(endIso ?? '');
    if (start == null || end == null || end.isBefore(start)) return 'N/A';

    final diff = end.difference(start);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    if (hours <= 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  String _formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Widget _buildFlightOptionCard(dynamic it) {
    final logoUrl = _flightLogoProxyUrl(it);
    final segments = (it['segments'] is List) ? it['segments'] as List : [];

    final firstSeg = (segments.isNotEmpty && segments.first is Map)
        ? segments.first as Map
        : null;
    final lastSeg = (segments.isNotEmpty && segments.last is Map)
        ? segments.last as Map
        : null;

    final depCode =
        (it['departureCode'] ?? firstSeg?['departure'] ?? '---').toString();
    final arrCode =
        (it['arrivalCode'] ?? lastSeg?['arrival'] ?? '---').toString();
    final depIso = (it['departure'] ?? firstSeg?['departureTime'])?.toString();
    final arrIso = (it['arrival'] ?? lastSeg?['arrivalTime'])?.toString();
    final depTime = _formatTimeOnly(depIso);
    final arrTime = _formatTimeOnly(arrIso);
    final depDate = _formatDateTime(depIso).split(' ').first;
    final arrDate = _formatDateTime(arrIso).split(' ').first;
    final duration = _formatDuration(depIso, arrIso);
    final stopCount = int.tryParse('${it['stops'] ?? 0}') ?? 0;
    final stopLabel = stopCount == 0
        ? 'Non-stop'
        : '$stopCount stop${stopCount > 1 ? 's' : ''}';
    final airlineName =
        (it['airline'] ?? firstSeg?['airline'] ?? 'Flight').toString();
    final flightCode =
        '${it['airlineCode'] ?? firstSeg?['flightCode'] ?? ''}${it['flightNumber'] ?? firstSeg?['flightNumber'] ?? ''}'
            .trim();
    final fareFamily =
        (it['fareFamily'] ?? firstSeg?['fareFamily'] ?? 'Standard').toString();

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logoUrl != null)
                  Image.network(
                    logoUrl,
                    width: 32,
                    height: 32,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.flight, size: 24),
                  )
                else
                  const Icon(Icons.flight, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        airlineName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        flightCode.isEmpty ? 'Flight option' : flightCode,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${it['price'] ?? it['showOurprice'] ?? it['totalFare'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      'per traveler',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(depTime,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(depCode,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(depDate,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        Text(duration,
                            style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1.8,
                                color: Colors.indigo.shade100,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.flight,
                                  size: 16, color: Colors.indigo.shade400),
                            ),
                            Expanded(
                              child: Container(
                                height: 1.8,
                                color: Colors.indigo.shade100,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(stopLabel,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 11)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(arrTime,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(arrCode,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(arrDate,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _flightInfoChip('Fare', fareFamily,
                    backgroundColor: Colors.indigo.shade50,
                    textColor: Colors.indigo.shade700),
                _flightInfoChip(
                    'Ticketing', '${it['ticketingTime'] ?? 'N/A'} mins',
                    backgroundColor: Colors.orange.shade50,
                    textColor: Colors.orange.shade800),
                _flightInfoChip('Stops', '$stopCount',
                    backgroundColor: Colors.grey.shade100),
              ],
            ),
            if (it['baseFare'] != null ||
                it['taxes'] != null ||
                it['totalFare'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Base: ${it['baseFare'] ?? 'N/A'}   Taxes: ${it['taxes'] ?? 'N/A'}   Total: ${it['totalFare'] ?? 'N/A'}',
                    style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _showFlightDetails(it),
                  child: const Text('View Details'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _selectCard(it),
                  child: const Text('Select Flight'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    final txt =
        (value == null || value.toString().isEmpty) ? 'N/A' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              txt,
              style: TextStyle(color: Colors.grey[800], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flightInfoChip(String label, String value,
      {Color? backgroundColor, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _timelineMarker({required bool isLast}) {
    return SizedBox(
      width: 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
            ),
          ),
          if (!isLast)
            Container(
              width: 2,
              height: 34,
              margin: const EdgeInsets.only(top: 2),
              color: Colors.indigo.shade100,
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentTile(Map<String, dynamic> seg, {required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _timelineMarker(isLast: isLast),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${seg['airline'] ?? 'Airline'} ${seg['flightCode'] ?? ''}${seg['flightNumber'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if ((seg['remainingSeats'] ?? '').toString() != 'N/A')
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${seg['remainingSeats'] ?? 'N/A'} seats left',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seg['departurelocation']?.toString() ??
                                seg['departure']?.toString() ??
                                'Departure',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${seg['departureairport'] ?? seg['departairport'] ?? ''}\n${_formatDateTime(seg['departureTime']?.toString())}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Column(
                        children: [
                          Icon(Icons.flight_takeoff,
                              size: 18, color: Colors.indigo.shade300),
                          const SizedBox(height: 4),
                          Container(
                            width: 64,
                            height: 2,
                            color: Colors.indigo.shade100,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            seg['arrivallocation']?.toString() ??
                                seg['arrival']?.toString() ??
                                'Arrival',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${seg['arrivalairport'] ?? seg['arrivalairport'] ?? ''}\n${_formatDateTime(seg['arrivalTime']?.toString())}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700]),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _flightInfoChip('Cabin', seg['cabin']?.toString() ?? 'N/A',
                        backgroundColor: Colors.grey.shade50),
                    _flightInfoChip(
                        'Duration', '${seg['triptime'] ?? 'N/A'} mins',
                        backgroundColor: Colors.grey.shade50),
                    _flightInfoChip('Leg', '${seg['legindicator'] ?? 'N/A'}',
                        backgroundColor: Colors.grey.shade50),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showFlightDetails(dynamic it) {
    final logoUrl = _flightLogoProxyUrl(it);
    final segments =
        (it['segments'] is List) ? it['segments'] as List : <dynamic>[];
    final taxBreakUp =
        (it['taxBreakUp'] is List) ? it['taxBreakUp'] as List : <dynamic>[];
    final penalties = (it['penaltyDetails'] is List)
        ? it['penaltyDetails'] as List
        : <dynamic>[];
    final rawFlight = it['rawFlight'] ?? it;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade700, Colors.indigo.shade500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: logoUrl != null
                              ? Image.network(
                                  logoUrl,
                                  width: 26,
                                  height: 26,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.flight,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.flight, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it['airline'] ?? 'Flight Details',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${it['departureCode'] ?? ''} → ${it['arrivalCode'] ?? ''} • ${it['fareFamily'] ?? 'Fare not specified'}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF6F8FB),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            it['name'] ?? 'Flight Option',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          // Text(
                                          //   'Ref: ${it['fareSourceCode'] ?? 'N/A'}',
                                          //   style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                          // ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '\$${it['price'] ?? it['showOurprice'] ?? it['totalFare'] ?? 'N/A'}',
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green),
                                        ),
                                        Text(
                                          'per traveler',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _flightInfoChip(
                                        'Stops', '${it['stops'] ?? 0}',
                                        backgroundColor: Colors.indigo.shade50,
                                        textColor: Colors.indigo.shade700),
                                    _flightInfoChip('Ticketing',
                                        '${it['ticketingTime'] ?? 'N/A'} mins',
                                        backgroundColor: Colors.orange.shade50,
                                        textColor: Colors.orange.shade800),
                                    _flightInfoChip('Exchange',
                                        '${it['exchangeTime'] ?? 'N/A'}',
                                        backgroundColor: Colors.blue.shade50,
                                        textColor: Colors.blue.shade800),
                                    _flightInfoChip(
                                        'Void', '${it['voidTime'] ?? 'N/A'}',
                                        backgroundColor: Colors.purple.shade50,
                                        textColor: Colors.purple.shade800),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle('Flight itinerary',
                                    subtitle:
                                        'Detailed segment-by-segment journey view'),
                                const SizedBox(height: 14),
                                if (segments.isEmpty)
                                  Text('No segment details available',
                                      style: TextStyle(color: Colors.grey[700]))
                                else
                                  ...segments
                                      .asMap()
                                      .entries
                                      .map<Widget>((entry) {
                                    final index = entry.key;
                                    final seg = Map<String, dynamic>.from(
                                        entry.value as Map);
                                    return _buildSegmentTile(seg,
                                        isLast: index == segments.length - 1);
                                  }).toList(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle('Fare & pricing'),
                                const SizedBox(height: 10),
                                _detailRow(
                                    'Departure airport',
                                    it['departureLocation'] ??
                                        it['departureCode']),
                                _detailRow('Arrival airport',
                                    it['arrivalLocation'] ?? it['arrivalCode']),
                                _detailRow('Displayed price', it['price']),
                                _detailRow('Base fare', it['baseFare']),
                                _detailRow('Taxes', it['taxes']),
                                _detailRow('Total fare', it['totalFare']),
                                const SizedBox(height: 8),
                                if (taxBreakUp.isNotEmpty) ...[
                                  const Divider(),
                                  const SizedBox(height: 4),
                                  _sectionTitle('Tax breakup'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: taxBreakUp.map<Widget>((tax) {
                                      return _flightInfoChip(
                                        tax['taxCode']?.toString() ?? 'Tax',
                                        tax['amount']?.toString() ?? 'N/A',
                                        backgroundColor: Colors.grey.shade50,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle('Rules & penalties'),
                                const SizedBox(height: 10),
                                if (penalties.isEmpty)
                                  Text('No penalty details available',
                                      style: TextStyle(color: Colors.grey[700]))
                                else
                                  ...penalties.map<Widget>((p) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _flightInfoChip('Pax',
                                              p['paxType']?.toString() ?? 'N/A',
                                              backgroundColor: Colors.white),
                                          _flightInfoChip(
                                              'Refund allowed',
                                              p['refundAllowed']?.toString() ??
                                                  'N/A',
                                              backgroundColor: Colors.white),
                                          _flightInfoChip(
                                              'Refund penalty',
                                              p['refundPenaltyAmount']
                                                      ?.toString() ??
                                                  'N/A',
                                              backgroundColor: Colors.white),
                                          _flightInfoChip(
                                              'Change allowed',
                                              p['changeAllowed']?.toString() ??
                                                  'N/A',
                                              backgroundColor: Colors.white),
                                          _flightInfoChip(
                                              'Change penalty',
                                              p['changePenaltyAmount']
                                                      ?.toString() ??
                                                  'N/A',
                                              backgroundColor: Colors.white),
                                          _flightInfoChip(
                                              'Currency',
                                              p['currency']?.toString() ??
                                                  'N/A',
                                              backgroundColor: Colors.white),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHotelOptionCard(dynamic it) {
    final starRating = it['starRating'] is num
        ? (it['starRating'] as num).toDouble()
        : double.tryParse(it['starRating']?.toString() ?? '');
    final starCount = starRating != null ? starRating.floor() : 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (it['heroImage'] != null &&
                it['heroImage'].toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _proxyImageUrl(it['heroImage'].toString()),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 150,
                    color: Colors.grey[300],
                    child:
                        const Icon(Icons.hotel, size: 50, color: Colors.grey),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(it['name'] ?? 'Hotel Option',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (starCount > 0)
                  Row(
                    children: List.generate(
                      starCount,
                      (index) =>
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '\$${it['ourprice'] ?? 'N/A'}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
                if (it['saving'] != null && it['saving'] > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Save \$${it['saving']}',
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (it['distance'] != null)
              Text(
                '${it['distance'].toStringAsFixed(1)} km from center',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            if (it['contact'] != null && it['contact']['address'] != null)
              Text(
                '${it['contact']['address']['city']?['name'] ?? ''}, ${it['contact']['address']['country']?['name'] ?? ''}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            const SizedBox(height: 8),
            if (it['reviews'] != null)
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  Text(
                    '${it['reviews']['rating'] ?? 'N/A'} (${it['reviews']['count'] ?? 0} reviews)',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (it['mainamenity'] != null && it['mainamenity'] is List)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: (it['mainamenity'] as List)
                    .map<Widget>((amenity) => Chip(
                          label: Text(amenity,
                              style: const TextStyle(fontSize: 10)),
                          backgroundColor: Colors.blue.shade50,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _showHotelDetails(it),
                  child: const Text('View Details'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _selectCard(it),
                  child: const Text('Select'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2a3f5f),
              Color(0xFF1e3c72),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(
            top: BorderSide(
              color: Color(0xFF667eea).withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Start with dates',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose dates first, then add travelers.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.84),
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildPlannerActionButton(
                          icon: Icons.hotel,
                          title: 'Hotel',
                          subtitle: 'Stay dates',
                          onPressed: () => _openTripPlanner(
                            initialType: TripPlannerType.hotel,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPlannerActionButton(
                          icon: Icons.flight_takeoff,
                          title: 'Flight',
                          subtitle: 'Departure date',
                          onPressed: () => _openTripPlanner(
                            initialType: TripPlannerType.flight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: TextField(
                      controller: inputCtrl,
                      onSubmitted: _send,
                      style: TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Ask me anything about flights or hotels...',
                        hintStyle: TextStyle(color: Colors.black),
                        fillColor: Colors.white.withOpacity(0.95),
                        filled: true,
                        prefixIcon:
                            Icon(Icons.search, color: Color(0xFF667eea)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: loading
                      ? Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        )
                      : FloatingActionButton(
                          onPressed: () => _send(inputCtrl.text),
                          mini: true,
                          backgroundColor: Color(0xFF667eea),
                          child: Icon(Icons.send, color: Colors.white),
                        ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _browseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Search Hotels',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
              controller: cityCtrl,
              decoration: const InputDecoration(
                  labelText: 'City',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: checkInCtrl,
                    decoration: const InputDecoration(
                        labelText:
                            'Check-in (YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, June 2)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: checkOutCtrl,
                    decoration: const InputDecoration(
                        labelText:
                            'Check-out (YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, 2nd June)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(
                onPressed: _searchHotels,
                icon: const Icon(Icons.search),
                label: const Text('Search')),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('Results appear in the Chat tab.',
                    style: TextStyle(color: Colors.grey))),
          ])
        ],
      ),
    );
  }

  Future<void> _showHotelDetails(dynamic hotel) async {
    setState(() => loading = true);

    try {
      final hotelId = hotel['id'] ?? hotel['hotelId'] ?? hotel['result']?['id'] ?? hotel['result']?['hotelId'];
      if (hotelId == null || hotelId.toString().isEmpty) {
        _bot('Unable to determine hotel id for details request.');
        return;
      }

      // Fetch hotel details from backend proxy
      final requestToken = hotel['token']?.toString() ??
          hotel['hotelToken']?.toString() ??
          hotel['result']?['token']?.toString() ??
          lastToken ??
          '';
      final requestCorrelationId = hotel['correlationId']?.toString() ??
          hotel['result']?['correlationId']?.toString() ??
          lastCorrelationId ??
          '';

      final detailsResponse = await http.post(
        Uri.parse('$base/mcp/hotel/get-hotel-details'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'hotelId': hotelId.toString(),
          if (requestToken.isNotEmpty) 'token': requestToken,
          if (requestCorrelationId.isNotEmpty)
            'correlationId': requestCorrelationId,
          'contentType': 'ALL',
        }),
      );

      debugPrint(
          'Hotel details response status: ${detailsResponse.statusCode}');
      debugPrint('Hotel details response body: ${detailsResponse.body}');

      if (detailsResponse.statusCode < 200 ||
          detailsResponse.statusCode >= 300) {
        final msg = detailsResponse.body.isNotEmpty
            ? detailsResponse.body
            : 'Unknown error';
        _bot(
            'Failed to load hotel details: ${detailsResponse.statusCode}. $msg');
        return;
      }

      final dynamic details = json.decode(detailsResponse.body);
      if (details == null) {
        _bot('Failed to parse hotel details response.');
        return;
      }

      // token may be in root or nested result, ensure fallback
      final token = (details is Map)
          ? (details['token'] ??
              details['result']?['token'] ??
              details['result']?['content']?['token'] ??
              hotel['token'] ??
              hotel['hotelToken'] ??
              hotel['result']?['token'] ??
              '')
          : '';

      final today = DateTime.now();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final checkIn = hotel['checkIn']?.toString().isNotEmpty == true
          ? hotel['checkIn'].toString()
          : '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final checkOut = hotel['checkOut']?.toString().isNotEmpty == true
          ? hotel['checkOut'].toString()
          : '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      final rooms =
          (hotel['rooms'] is List && (hotel['rooms'] as List).isNotEmpty)
              ? hotel['rooms']
              : [
                  {
                    'childAges': [],
                    'children': 0,
                    'adults': 2,
                  }
                ];

      // Fetch hotel details and rates from backend proxy using the token
      dynamic rates;
      final ratesCorrelationId = hotel['correlationId']?.toString() ??
          hotel['result']?['correlationId']?.toString() ??
          lastCorrelationId ??
          '';
      if (token is String && token.isNotEmpty) {
        final ratesResponse = await http.post(
          Uri.parse('$base/mcp/hotel/get-hotel-details-and-rates'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'token': token,
            'hotelId': hotelId.toString(),
            'checkIn': checkIn,
            'checkOut': checkOut,
            'rooms': rooms,
            if (ratesCorrelationId.isNotEmpty)
              'correlationId': ratesCorrelationId,
          }),
        );

        debugPrint(
            'Hotel details/rates response status: ${ratesResponse.statusCode}');
        debugPrint('Hotel details/rates response body: ${ratesResponse.body}');

        if (ratesResponse.statusCode == 200 ||
            ratesResponse.statusCode == 201) {
          rates = json.decode(ratesResponse.body);
        } else {
          debugPrint('Room rates load failed; showing details without rates.');
        }
      } else {
        debugPrint('Hotel rate token missing; showing details without rates.');
      }

      _showHotelDetailsDialog(hotel, details, rates);
    } catch (e, st) {
      debugPrint('Error in _showHotelDetails: $e\n$st');
      _bot('Error loading hotel details: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  double? _priceForFlightCard(dynamic flightCard) {
    if (flightCard is! Map) return null;

    final candidates = [
      flightCard['price'],
      flightCard['showOurprice'],
      flightCard['totalFare'],
      flightCard['baseFare'],
      flightCard['key_0'],
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final parsed = double.tryParse(candidate.toString().replaceAll(',', ''));
      if (parsed != null) return parsed;
    }

    return null;
  }

  List<dynamic> _sortFlightCardsByPrice(List<dynamic> flightCards) {
    if (flightCards.length < 2) return List<dynamic>.from(flightCards);

    final sortedCards = List<dynamic>.from(flightCards);
    if (_flightSortMode == HotelSortMode.defaultOrder) return sortedCards;

    sortedCards.sort((left, right) {
      final leftPrice = _priceForFlightCard(left);
      final rightPrice = _priceForFlightCard(right);

      if (leftPrice == null && rightPrice == null) return 0;
      if (leftPrice == null) return 1;
      if (rightPrice == null) return -1;

      return _flightSortMode == HotelSortMode.priceLowToHigh
          ? leftPrice.compareTo(rightPrice)
          : rightPrice.compareTo(leftPrice);
    });

    return sortedCards;
  }

  Widget _buildFlightTabs(List<dynamic> flightCards) {
    final sortedCards = _sortFlightCardsByPrice(flightCards);
    final groups = _chunkCards(sortedCards, 3);
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortControls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sort flights by price',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        _buildPriceSortControls(
          selectedMode: _flightSortMode,
          onChanged: (mode) {
            setState(() => _flightSortMode = mode);
          },
        ),
      ],
    );

    if (groups.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sortControls,
          const SizedBox(height: 12),
          ...groups.first.map((it) => _buildFlightOptionCard(it)).toList(),
        ],
      );
    }

    return DefaultTabController(
      length: groups.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sortControls,
          const SizedBox(height: 12),
          TabBar(
            isScrollable: true,
            indicatorColor: Colors.indigo,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey[700],
            tabs: [
              for (var index = 0; index < groups.length; index++)
                Tab(
                    text:
                        '${index * 3 + 1}-${index * 3 + groups[index].length}'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 980,
            child: TabBarView(
              children: [
                for (final group in groups)
                  SingleChildScrollView(
                    child: Column(
                      children: group
                          .map((it) => _buildFlightOptionCard(it))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHotelDetailsDialog(dynamic hotel, dynamic details, dynamic rates) {
    Map<String, dynamic> _ensureMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    List<dynamic> _roomsFromMap(Map<String, dynamic> map) {
      if (map['rooms'] is List) {
        return List<dynamic>.from(map['rooms'] as List);
      }
      if (map['rooms'] is Map) {
        return List<dynamic>.from((map['rooms'] as Map).values);
      }
      return <dynamic>[];
    }

    List<dynamic> _extractRooms(dynamic source) {
      if (source is! Map) return <dynamic>[];
      final sourceMap = _ensureMap(source);

      if (sourceMap['result'] is Map) {
        final resultMap = _ensureMap(sourceMap['result']);
        if (resultMap['content'] is Map) {
          final contentMap = _ensureMap(resultMap['content']);
          final rooms = _roomsFromMap(contentMap);
          if (rooms.isNotEmpty) return rooms;
        }
        final rooms = _roomsFromMap(resultMap);
        if (rooms.isNotEmpty) return rooms;
      }

      if (sourceMap['content'] is Map) {
        final contentMap = _ensureMap(sourceMap['content']);
        final rooms = _roomsFromMap(contentMap);
        if (rooms.isNotEmpty) return rooms;
      }

      return _roomsFromMap(sourceMap);
    }

    Map<String, dynamic> hotelData = {};
    if (details is Map) {
      final detailsMap = _ensureMap(details);
      if (detailsMap['result'] is Map) {
        final resultMap = _ensureMap(detailsMap['result']);
        if (resultMap['content'] is Map) {
          hotelData = _ensureMap(resultMap['content']);
        } else if (resultMap['hotel'] is Map) {
          hotelData = _ensureMap(resultMap['hotel']);
        } else {
          hotelData = resultMap;
        }
      } else if (detailsMap['content'] is Map) {
        hotelData = _ensureMap(detailsMap['content']);
      } else {
        hotelData = detailsMap;
      }
    }

    final roomsData = _extractRooms(rates);
    final List<dynamic> images =
        hotelData['images'] is List ? List<dynamic>.from(hotelData['images'] as List) : <dynamic>[];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Hotel Details',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.95,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 16,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              hotelData['name'] ??
                                  hotel['name'] ??
                                  'Hotel Details',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hotelData['heroImage'] != null ||
                                hotel['heroImage'] != null)
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 520),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      _proxyImageUrl((hotelData['heroImage'] ??
                                              hotel['heroImage'])
                                          .toString()),
                                      height: 220,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                        height: 220,
                                        color: Colors.grey[300],
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.hotel,
                                            size: 54, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            const SizedBox(height: 16),
                            _buildSectionHeader('Quick Summary'),
                            _buildInfoRow('Hotel ID',
                                hotelData['id'] ?? hotel['id'] ?? 'N/A'),
                            if (hotelData['starRating'] != null)
                              _buildInfoRow('Star Rating',
                                  '${hotelData['starRating']} stars'),
                            if (hotelData['providerName'] != null)
                              _buildInfoRow(
                                  'Provider', hotelData['providerName']),
                            if (hotel['ourprice'] != null)
                              _buildInfoRow(
                                  'Nightly Price', '\$${hotel['ourprice']}'),
                            const SizedBox(height: 16),
                            _buildSectionHeader('Location'),
                            if (hotelData['contact'] != null &&
                                hotelData['contact']['address'] != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${hotelData['contact']['address']['line1'] ?? ''}',
                                      style: const TextStyle(fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${hotelData['contact']['address']['city']?['name'] ?? ''}, ${hotelData['contact']['address']['state']?['name'] ?? ''} ${hotelData['contact']['address']['postalCode'] ?? ''}',
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.black87),
                                  ),
                                  Text(
                                      '${hotelData['contact']['address']['country']?['name'] ?? ''}',
                                      style: const TextStyle(
                                          fontSize: 14, color: Colors.black87)),
                                  if (hotelData['geoCode'] != null)
                                    Text(
                                        'Coords: ${hotelData['geoCode']['lat']}, ${hotelData['geoCode']['long']}',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12)),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            if (hotelData['descriptions'] != null &&
                                hotelData['descriptions'] is List) ...[
                              _buildSectionHeader('Descriptions'),
                              ...((hotelData['descriptions'] as List)
                                  .map<Widget>((dynamic desc) {
                                final type = (desc['type'] ?? '')
                                    .toString()
                                    .replaceAll('_', ' ')
                                    .toUpperCase();
                                final text = desc['text'] ?? '';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (type.isNotEmpty)
                                        Text(type,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: Colors.indigo)),
                                      if (text.isNotEmpty)
                                        Text(text,
                                            style: const TextStyle(
                                                fontSize: 14, height: 1.35)),
                                    ],
                                  ),
                                );
                              })),
                              const SizedBox(height: 12),
                            ],
                            if (hotelData['facilities'] != null &&
                                hotelData['facilities'] is List) ...[
                              _buildSectionHeader('Facilities'),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: (hotelData['facilities'] as List)
                                    .map<Widget>((facility) => Chip(
                                          label: Text(
                                              facility['name'] ?? 'Unknown',
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          backgroundColor: Colors.blue.shade50,
                                          visualDensity: VisualDensity.compact,
                                        ))
                                    .toList(),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (hotelData['nearByAttractions'] != null &&
                                hotelData['nearByAttractions'] is List) ...[
                              _buildSectionHeader('Nearby Attractions'),
                              ...((hotelData['nearByAttractions'] as List)
                                  .map<Widget>((attraction) => Text(
                                      '• ${attraction['name']} (${attraction['distance']} ${attraction['unit']})',
                                      style: const TextStyle(
                                          fontSize: 14)))).toList(),
                              const SizedBox(height: 12),
                            ],
                            if (images.isNotEmpty) ...[
                              _buildSectionHeader('Photo Gallery'),
                              ImageCarouselWidget(
                                gallery: ImageGalleryModel.fromImageList(
                                  images,
                                  hotelData['name'] ?? hotel['name'],
                                ),
                                proxyImageUrl: _proxyImageUrl,
                                primaryColor: Colors.indigo,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (roomsData.isNotEmpty) ...[
                              _buildSectionHeader('Rooms & Rates'),
                              ...roomsData.map<Widget>((room) {
                                final ratesList = (room['rates'] is List)
                                    ? room['rates'] as List
                                    : [];
                                final totalAmount = ratesList.isNotEmpty &&
                                        ratesList.first['total'] is Map
                                    ? ((ratesList.first['total']
                                            as Map)['amount']
                                        ?.toString())
                                    : null;
                                final policy = ratesList.isNotEmpty &&
                                        ratesList.first['cancellation_policy']
                                            is Map
                                    ? ((ratesList.first['cancellation_policy']
                                        as Map)['description'])
                                    : null;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(room['name'] ?? 'Room',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        if (room['descriptions'] != null &&
                                            room['descriptions']['overview'] !=
                                                null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 6, bottom: 6),
                                            child: Text(
                                                room['descriptions']
                                                        ['overview'] ??
                                                    '',
                                                style: TextStyle(
                                                    color: Colors.grey[700])),
                                          ),
                                        Text(
                                            'Max occupancy: ${room['occupancy']?['max_allowed']?['total'] ?? 'N/A'}',
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        if (totalAmount != null)
                                          Text('Price: \$$totalAmount',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green)),
                                        if (policy != null)
                                          Text('Policy: $policy',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                            if (hotelData['eanReviews'] != null &&
                                hotelData['eanReviews'] is List) ...[
                              _buildSectionHeader('Guest Reviews'),
                              ...((hotelData['eanReviews'] as List).take(5))
                                  .map<Widget>((review) => Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  review['reviewer_name'] ??
                                                      'Anonymous',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              Text(review['text'] ?? '',
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                              const SizedBox(height: 6),
                                              Text(
                                                  'Rating: ${review['rating'] ?? 'N/A'}',
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey)),
                                              Text(
                                                  'Date: ${review['date_submitted']?.toString().split('T').first ?? 'N/A'}',
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey)),
                                            ],
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _selectCard(hotel);
                                  },
                                  child: const Text('Select This Hotel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.indigo,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _startNewChat() {
    setState(() {
      messages.clear();
      sessionId = Uuid().v4();
      loading = false;

      _pendingBookingQuery = null;
      _awaitingTravelerCounts = false;

      lastSearchCity = null;
      lastSearchCheckIn = null;
      lastSearchCheckOut = null;
      isWaitingForCheckOut = false;

      lastDestinationId = null;
      lastDestinationCode = null;
      lastToken = null;
      lastRecommendationId = null;
    });

    _bot('Hi — I can help you book flights or hotels. Try: "book a flight"');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RouteStack',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: false,
        elevation: 8,
        actions: [
          IconButton(
            onPressed: _startNewChat,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667eea),
                Color(0xFF764ba2),
                Color(0xFFf093fb),
              ],
            ),
          ),
        ),
      ),
      body: _chatTab(),
    );
  }
}
