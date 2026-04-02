/// Model for image gallery data
class ImageGalleryModel {
  final List<String> imageUrls;
  final String? hotelName;
  
  ImageGalleryModel({
    required this.imageUrls,
    this.hotelName,
  });

  /// Factory to create from dynamic list (from API response)
  factory ImageGalleryModel.fromImageList(List<dynamic> images, String? hotelName) {
    final urls = <String>[];
    for (final image in images) {
      if (image is String) {
        urls.add(image);
      } else if (image is Map) {
        String? url;
        if (image['url'] is String) url = image['url'];
        else if (image['href'] is String) url = image['href'];
        else if (image['heroImage'] is String) url = image['heroImage'];
        else if (image['links'] is List) {
          for (final link in image['links'] as List) {
            if (link is Map && link['url'] is String) {
              url = link['url'] as String;
              break;
            }
          }
        } else if (image['links'] is Map) {
          final linksMap = image['links'] as Map;
          for (final entry in linksMap.values) {
            if (entry is Map && entry['url'] is String) {
              url = entry['url'] as String;
              break;
            }
            if (entry is String && entry.startsWith('http')) {
              url = entry;
              break;
            }
          }
        }
        
        if (url != null) urls.add(url);
      }
    }
    
    return ImageGalleryModel(
      imageUrls: urls,
      hotelName: hotelName,
    );
  }

  bool get isEmpty => imageUrls.isEmpty;
  int get length => imageUrls.length;
  bool get canNavigate => length > 1;
  
  String getImageUrl(int index) => 
    index >= 0 && index < imageUrls.length ? imageUrls[index] : '';
}

/// Model for carousel state
class CarouselState {
  final int currentIndex;
  final ImageGalleryModel gallery;
  final bool isLoading;
  final String? error;

  CarouselState({
    required this.currentIndex,
    required this.gallery,
    this.isLoading = false,
    this.error,
  });

  /// Copy with method for state updates
  CarouselState copyWith({
    int? currentIndex,
    ImageGalleryModel? gallery,
    bool? isLoading,
    String? error,
  }) {
    return CarouselState(
      currentIndex: currentIndex ?? this.currentIndex,
      gallery: gallery ?? this.gallery,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get hasNextImage => currentIndex < gallery.length - 1;
  bool get hasPreviousImage => currentIndex > 0;
  bool get canNavigate => gallery.length > 1;
}
