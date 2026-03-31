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
              final mainFlight = flight['flights'] != null 
                ? flight['flights'][0] 
                : null;
              
              if (mainFlight != null) {
                return {
                  'id': flight['fareSourceCode'] ?? 'flight_${results.indexOf(flight)}',
                  'fareSourceCode': flight['fareSourceCode'],
                  'key_0': flight['coin'] ?? flight['showOurprice'] ?? flight['totalFare'],
                  'name': '${mainFlight['airline']} ${mainFlight['flightCode']}${mainFlight['flightNumber']}',
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
    if (data['cards'] != null && data['cards'] is List && data['cards'].isNotEmpty) {
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
    final price = it['price'] ?? 'N/A';
    setState(
      () => messages.insert(0, ChatMessage('$name — \$$price', fromUser: true)),
    );
    setState(() => loading = true);

    try {
      final r = await http.post(
        Uri.parse('$base/chat'),
        body: json.encode({
          'sessionId': sessionId,
          'message': 'select:${it['id']}|${it['key_0'] ?? it['coin'] ?? it['showOurprice'] ?? it['totalFare'] ?? ''}',
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: m.fromUser ? Colors.indigo.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
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
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.text != null) 
              Padding(
                padding: const EdgeInsets.only(bottom: 8), 
                child: Text(m.text!, style: const TextStyle(fontWeight: FontWeight.w600))
              ),
            ...m.cards!.map((it) => Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                title: Text(it['name'] ?? 'Available Option', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('\$${it['price'] ?? '0'}'),
                trailing: ElevatedButton(
                  onPressed: () => _selectCard(it),
                  child: const Text('Select'),
                ),
              ),
            )).toList(),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
          const Text('Search Hotels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City', filled: true, fillColor: Colors.white, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: checkInCtrl, decoration: const InputDecoration(labelText: 'Check-in (YYYY-MM-DD)', filled: true, fillColor: Colors.white, border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: checkOutCtrl, decoration: const InputDecoration(labelText: 'Check-out (YYYY-MM-DD)', filled: true, fillColor: Colors.white, border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(onPressed: _searchHotels, icon: const Icon(Icons.search), label: const Text('Search')),
            const SizedBox(width: 12),
            const Expanded(child: Text('Results appear in the Chat tab.', style: TextStyle(color: Colors.grey))),
          ])
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
          bottom: const TabBar(tabs: [Tab(text: 'Chat'), Tab(text: 'Browse')])
        ),
        body: TabBarView(children: [_chatTab(), _browseTab()]),
      ),
    );
  }
}