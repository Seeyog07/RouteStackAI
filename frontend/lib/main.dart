import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

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
  final inputCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final checkInCtrl = TextEditingController();
  final checkOutCtrl = TextEditingController();
  String? sessionId;
  bool loading = false;

  String get base {
    if (kIsWeb) return 'http://localhost:3000/api';
    return 'http://10.0.2.2:3000/api';
  }

  @override
  void initState() {
    super.initState();
    sessionId = Uuid().v4();
    _bot('Hi — I can help you book flights or hotels. Try: "book a flight"');
  }

  void _bot(String text) {
    setState(() => messages.insert(0, ChatMessage(text, fromUser: false)));
  }

  /// Handles the API response and converts technical errors into conversation
  void _handleApiResponse(Map<String, dynamic> data) {
    sessionId = data['sessionId'] ?? sessionId;

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
                  'price': flight['showOurprice'] ?? flight['totalFare'] ?? '0',
                  'stops': flight['stops'] ?? 0,
                  'departure': mainFlight['departureTime'],
                  'arrival': mainFlight['arrivalTime'],
                };
              }
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
      setState(
        () => messages.insert(
          0,
          ChatMessage(reply, fromUser: false, cards: cards),
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

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;

    final String userDisplayMessage = text;
    setState(() {
      messages.insert(0, ChatMessage(userDisplayMessage, fromUser: true));
      loading = true;
    });
    inputCtrl.clear();

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
    setState(
      () => messages.insert(0, ChatMessage('$name — \$$price', fromUser: true)),
    );
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

    // Send hotel search through chat
    final message = 'Hotel in $city from $checkIn to $checkOut';
    inputCtrl.text = message;
    await _send(message);
  }

  // --- UI BUILDING METHODS ---

  Widget _chatTab() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
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
        _buildInputArea(),
      ],
    );
  }

  Widget _buildTextMessage(ChatMessage m) {
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: m.fromUser ? Colors.indigo.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Text(m.text ?? '', style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _buildCardMessage(ChatMessage m) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
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
            ...m.cards!
                .map((it) => Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hotel image
                            if (it['heroImage'] != null &&
                                it['heroImage'].toString().isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  it['heroImage'],
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    height: 150,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.hotel,
                                        size: 50, color: Colors.grey),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            // Hotel name and rating
                            Row(
                              children: [
                                Expanded(
                                  child: Text(it['name'] ?? 'Hotel Option',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                                if (it['starRating'] != null &&
                                    it['starRating'] > 0)
                                  Row(
                                    children: List.generate(
                                      it['starRating'],
                                      (index) => const Icon(Icons.star,
                                          color: Colors.amber, size: 16),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Price and savings
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
                                          color: Colors.red,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Distance and location
                            if (it['distance'] != null)
                              Text(
                                '${it['distance'].toStringAsFixed(1)} km from center',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            if (it['contact'] != null &&
                                it['contact']['address'] != null)
                              Text(
                                '${it['contact']['address']['city']?['name'] ?? ''}, ${it['contact']['address']['country']?['name'] ?? ''}',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            const SizedBox(height: 8),
                            // Reviews
                            if (it['reviews'] != null)
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 14),
                                  Text(
                                    '${it['reviews']['rating'] ?? 'N/A'} (${it['reviews']['count'] ?? 0} reviews)',
                                    style: TextStyle(
                                        color: Colors.grey[700], fontSize: 12),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            // Main amenities
                            if (it['mainamenity'] != null &&
                                it['mainamenity'] is List)
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: (it['mainamenity'] as List)
                                    .map<Widget>((amenity) => Chip(
                                          label: Text(amenity,
                                              style: const TextStyle(
                                                  fontSize: 10)),
                                          backgroundColor: Colors.blue.shade50,
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ))
                                    .toList(),
                              ),
                            const SizedBox(height: 8),
                            // Action buttons
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
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: inputCtrl,
                onSubmitted: _send,
                decoration: InputDecoration(
                    hintText: 'Type your message...',
                    fillColor: Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : FloatingActionButton(
                    mini: true,
                    onPressed: () => _send(inputCtrl.text),
                    child: const Icon(Icons.send),
                  ),
          )
        ],
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
                        labelText: 'Check-in (YYYY-MM-DD)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: checkOutCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Check-out (YYYY-MM-DD)',
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
      // Fetch hotel details from backend proxy
      final detailsResponse = await http.post(
        Uri.parse('$base/mcp/hotel/get-hotel-details'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'hotelId': hotel['id'],
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
              hotel['token'] ??
              '')
          : '';

      // Fetch room rates from backend proxy using the token
      dynamic rates;
      if (token is String && token.isNotEmpty) {
        final ratesResponse = await http.post(
          Uri.parse('$base/mcp/hotel/get-rooms-and-rates'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'token': token,
            'hotelId': hotel['id'],
          }),
        );

        debugPrint(
            'Hotel rooms/rates response status: ${ratesResponse.statusCode}');
        debugPrint('Hotel rooms/rates response body: ${ratesResponse.body}');

        if (ratesResponse.statusCode == 200) {
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

  void _showHotelDetailsDialog(dynamic hotel, dynamic details, dynamic rates) {
    final Map<String, dynamic> hotelData = (details is Map)
        ? (details['result'] is Map<String, dynamic>
            ? details['result']
            : details)
        : {};
    final List<dynamic> roomsData = (rates is Map)
        ? (rates['result']?['rooms'] is List
            ? rates['result']['rooms']
            : (rates['rooms'] is List ? rates['rooms'] : []))
        : [];
    final List<dynamic> images =
        hotelData['images'] is List ? hotelData['images'] : [];

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
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _proxyImageUrl((hotelData['heroImage'] ??
                                          hotel['heroImage'])
                                      .toString()),
                                  height: 220,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    height: 220,
                                    color: Colors.grey[300],
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.hotel,
                                        size: 54, color: Colors.grey),
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
                              SizedBox(
                                height: 130,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: images.length,
                                  itemBuilder: (context, index) {
                                    final image = images[index];
                                    final imageUrl = _resolveImageUrl(image);

                                    if (imageUrl == null)
                                      return const SizedBox.shrink();

                                    final proxiedImageUrl =
                                        _proxyImageUrl(imageUrl);

                                    return Container(
                                      width: 130,
                                      margin: const EdgeInsets.only(right: 8),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          proxiedImageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Container(
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.image,
                                                color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('RouteStack Chat'),
            bottom:
                const TabBar(tabs: [Tab(text: 'Chat'), Tab(text: 'Browse')])),
        body: TabBarView(children: [_chatTab(), _browseTab()]),
      ),
    );
  }
}
