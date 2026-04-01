import 'package:flutter/material.dart';
import '../models/image_carousel_model.dart';

/// ViewModel for managing carousel logic and state
class ImageCarouselViewModel extends ChangeNotifier {
  CarouselState _state;

  ImageCarouselViewModel(ImageGalleryModel gallery)
      : _state = CarouselState(
          currentIndex: 0,
          gallery: gallery,
        );

  // Getters
  CarouselState get state => _state;
  int get currentIndex => _state.currentIndex;
  ImageGalleryModel get gallery => _state.gallery;
  String get currentImageUrl => gallery.getImageUrl(currentIndex);
  bool get canGoNext => _state.hasNextImage;
  bool get canGoPrevious => _state.hasPreviousImage;
  bool get isLastImage => currentIndex == gallery.length - 1;

  /// Navigate to next image
  void nextImage() {
    if (canGoNext) {
      _updateState(_state.currentIndex + 1);
    }
  }

  /// Navigate to previous image
  void previousImage() {
    if (canGoPrevious) {
      _updateState(_state.currentIndex - 1);
    }
  }

  /// Go to specific image by index
  void goToImage(int index) {
    if (index >= 0 && index < gallery.length) {
      _updateState(index);
    }
  }

  /// Navigate using keyboard/swipe (direction: 1 for next, -1 for previous)
  void navigateByDirection(int direction) {
    final newIndex = currentIndex + direction;
    if (newIndex >= 0 && newIndex < gallery.length) {
      _updateState(newIndex);
    }
  }

  /// Reset to first image
  void reset() {
    if (currentIndex != 0) {
      _updateState(0);
    }
  }

  /// Internal state update method
  void _updateState(int newIndex) {
    _state = _state.copyWith(currentIndex: newIndex);
    notifyListeners();
  }

  /// Get image progress text (e.g., "1 / 5")
  String getImageCountText() => '${currentIndex + 1} / ${gallery.length}';
}
