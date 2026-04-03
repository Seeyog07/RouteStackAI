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
  final int? maxAdults;
  final int? maxChildren;
  final String? recommendationId;
  final String? priceAmount;
  final String? priceCurrency;
  final String? cancellationPolicy;
  final String? bedSummary;
  final List<String> amenities;
  final dynamic rateFull;

  RoomRate({
    required this.roomId,
    required this.roomName,
    this.description,
    this.maxOccupancy,
    this.maxAdults,
    this.maxChildren,
    this.recommendationId,
    this.priceAmount,
    this.priceCurrency,
    this.cancellationPolicy,
    this.bedSummary,
    this.amenities = const [],
    this.rateFull,
  });

  factory RoomRate.fromJson(dynamic roomData) {
    final ratesList =
        (roomData['rates'] is List) ? roomData['rates'] as List : [];
    final firstRate = ratesList.isNotEmpty ? ratesList.first : null;

    String? priceAmount;
    String? priceCurrency;
    if (firstRate != null && firstRate['total'] is Map) {
      priceAmount = firstRate['total']['amount']?.toString();
      priceCurrency = firstRate['total']['currency']?.toString() ?? 'USD';
    }

    String? cancellationPolicy;
    if (firstRate != null && firstRate['cancellation_policy'] is Map) {
      cancellationPolicy =
          firstRate['cancellation_policy']['description']?.toString();
    }

    final occupancy = roomData['occupancy']?['max_allowed'];
    final maxOccupancy = occupancy?['total'] as int?;
    final maxAdults = occupancy?['adults'] as int?;
    final maxChildren = occupancy?['children'] as int?;

    final bedGroups = roomData['bed_groups'];
    String? bedSummary;
    if (bedGroups is Map && bedGroups.isNotEmpty) {
      final firstBedGroup = bedGroups.values.first;
      if (firstBedGroup is Map) {
        bedSummary = firstBedGroup['description']?.toString();
      }
    }

    List<String> amenities = [];
    final amenitiesMap = roomData['amenities'];
    if (amenitiesMap is Map) {
      amenities = amenitiesMap.values
          .whereType<Map>()
          .map((a) => a['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .take(6)
          .toList();
    }

    String? overview = roomData['descriptions']?['overview']?.toString();
    if (overview != null && overview.isNotEmpty) {
      overview = overview
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    return RoomRate(
      roomId: roomData['id']?.toString() ?? '',
      roomName: roomData['name'] ?? 'Standard Room',
      description: overview,
      maxOccupancy: maxOccupancy,
      maxAdults: maxAdults,
      maxChildren: maxChildren,
      recommendationId: roomData['recommendationId']?.toString(),
      priceAmount: priceAmount,
      priceCurrency: priceCurrency,
      cancellationPolicy: cancellationPolicy,
      bedSummary: bedSummary,
      amenities: amenities,
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
  String? get hotelPrice =>
      hotel['ourprice']?.toString() ?? hotel['price']?.toString();
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

    final url = json['paymentUrl'] ??
        json['payment_url'] ??
        json['url'] ??
        json['result']?['paymentUrl'] ??
        json['result']?['url'];
    final paymentUrl = url?.toString();
    return PaymentResult(
      success: json['success'] == true ||
          (paymentUrl != null && paymentUrl.isNotEmpty),
      paymentUrl: paymentUrl,
      message: json['message']?.toString(),
      rawData: json,
    );
  }
}
