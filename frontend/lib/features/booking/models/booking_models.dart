/// Models for booking operations

class RevalidationResult {
  final bool success;
  final String? token;
  final String? message;
  final dynamic rawData;

  RevalidationResult({
    required this.success,
    this.token,
    this.message,
    this.rawData,
  });

  factory RevalidationResult.fromJson(dynamic json) {
    if (json is! Map) {
      return RevalidationResult(
        success: false,
        message: 'Invalid response format',
        rawData: json,
      );
    }

    final token = json['token'] ?? json['result']?['token'];
    return RevalidationResult(
      success: json['success'] == true || token != null,
      token: token?.toString(),
      message: json['message']?.toString(),
      rawData: json,
    );
  }
}

class RoomRate {
  final String roomId;
  final String roomName;
  final String? description;
  final int? maxOccupancy;
  final String? priceAmount;
  final String? priceCurrency;
  final String? cancellationPolicy;
  final dynamic rateFull;

  RoomRate({
    required this.roomId,
    required this.roomName,
    this.description,
    this.maxOccupancy,
    this.priceAmount,
    this.priceCurrency,
    this.cancellationPolicy,
    this.rateFull,
  });

  factory RoomRate.fromJson(dynamic roomData) {
    final ratesList = (roomData['rates'] is List) ? roomData['rates'] as List : [];
    final firstRate = ratesList.isNotEmpty ? ratesList.first : null;

    String? priceAmount;
    String? priceCurrency;
    if (firstRate != null && firstRate['total'] is Map) {
      priceAmount = firstRate['total']['amount']?.toString();
      priceCurrency = firstRate['total']['currency']?.toString() ?? 'USD';
    }

    String? cancellationPolicy;
    if (firstRate != null && firstRate['cancellation_policy'] is Map) {
      cancellationPolicy = firstRate['cancellation_policy']['description']?.toString();
    }

    return RoomRate(
      roomId: roomData['id']?.toString() ?? '',
      roomName: roomData['name'] ?? 'Standard Room',
      description: roomData['descriptions']?['overview']?.toString(),
      maxOccupancy: roomData['occupancy']?['max_allowed']?['total'] as int?,
      priceAmount: priceAmount,
      priceCurrency: priceCurrency,
      cancellationPolicy: cancellationPolicy,
      rateFull: firstRate,
    );
  }

  String get displayPrice {
    if (priceAmount == null) return 'N/A';
    return '$priceCurrency $priceAmount';
  }
}

class BookingDetails {
  final dynamic hotel;
  final RevalidationResult revalidation;
  final List<RoomRate> rooms;

  BookingDetails({
    required this.hotel,
    required this.revalidation,
    required this.rooms,
  });

  bool get isValid => revalidation.success;
  String? get hotelName => hotel['name'];
  String? get hotelPrice => hotel['ourprice']?.toString() ?? hotel['price']?.toString();
}

class PaymentResult {
  final bool success;
  final String? paymentUrl;
  final String? message;
  final dynamic rawData;

  PaymentResult({
    required this.success,
    this.paymentUrl,
    this.message,
    this.rawData,
  });

  factory PaymentResult.fromJson(dynamic json) {
    if (json is! Map) {
      return PaymentResult(
        success: false,
        message: 'Invalid response format',
        rawData: json,
      );
    }

    final url = json['paymentUrl'] ?? json['payment_url'] ?? json['result']?['paymentUrl'];
    return PaymentResult(
      success: json['success'] == true || url != null,
      paymentUrl: url?.toString(),
      message: json['message']?.toString(),
      rawData: json,
    );
  }
}
