import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/image_carousel_model.dart';
import '../viewmodels/image_carousel_viewmodel.dart';
import 'image_lightbox_widget.dart';

/// Main carousel widget for hotel images with navigation
class ImageCarouselWidget extends StatefulWidget {
  final ImageGalleryModel gallery;
  final String Function(String) proxyImageUrl;
  final Color primaryColor;

  const ImageCarouselWidget({
    Key? key,
    required this.gallery,
    required this.proxyImageUrl,
    this.primaryColor = Colors.indigo,
  }) : super(key: key);

  @override
  State<ImageCarouselWidget> createState() => _ImageCarouselWidgetState();
}

class _ImageCarouselWidgetState extends State<ImageCarouselWidget> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gallery.isEmpty) {
      return SizedBox.shrink();
    }

    return ChangeNotifierProvider(
      create: (_) => ImageCarouselViewModel(widget.gallery),
      child: Consumer<ImageCarouselViewModel>(
        builder: (context, viewModel, _) {
          return Column(
            children: [
              // Main carousel image display
              _buildMainCarousel(context, viewModel),
              const SizedBox(height: 12),
              // Image counter and indicator dots
              if (widget.gallery.canNavigate)
                _buildImageIndicator(context, viewModel),
              const SizedBox(height: 8),
              // Thumbnail strip (optional, for quick preview)
              if (widget.gallery.length > 1)
                _buildThumbnailStrip(context, viewModel),
            ],
          );
        },
      ),
    );
  }

  /// Main carousel display with navigation buttons
  Widget _buildMainCarousel(
    BuildContext context,
    ImageCarouselViewModel viewModel,
  ) {
    final imageUrl =
        widget.proxyImageUrl(viewModel.currentImageUrl);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Main image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openLightbox(context, viewModel),
              child: Container(
                height: 300,
                color: Colors.grey[200],
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[300],
                    child: Icon(
                      Icons.image_not_supported,
                      size: 64,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Navigation buttons - prev
          if (viewModel.canGoPrevious)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildNavButton(
                  onPressed: () {
                    viewModel.previousImage();
                    _animatePageView(viewModel.currentIndex - 1);
                  },
                  icon: Icons.chevron_left,
                ),
              ),
            ),
          // Navigation buttons - next
          if (viewModel.canGoNext)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildNavButton(
                  onPressed: () {
                    viewModel.nextImage();
                    _animatePageView(viewModel.currentIndex + 1);
                  },
                  icon: Icons.chevron_right,
                ),
              ),
            ),
          // Click to expand hint
          Positioned(
            right: 12,
            bottom: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openLightbox(context, viewModel),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Click to expand',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigation button widget
  Widget _buildNavButton({
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: widget.primaryColor,
          size: 28,
        ),
        constraints: BoxConstraints(minWidth: 48, minHeight: 48),
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// Image counter and indicator dots
  Widget _buildImageIndicator(
    BuildContext context,
    ImageCarouselViewModel viewModel,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          viewModel.getImageCountText(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.gallery.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == viewModel.currentIndex
                        ? widget.primaryColor
                        : Colors.grey[300],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Thumbnail strip for quick navigation
  Widget _buildThumbnailStrip(
    BuildContext context,
    ImageCarouselViewModel viewModel,
  ) {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.gallery.length,
        itemBuilder: (context, index) {
          final imageUrl =
              widget.proxyImageUrl(widget.gallery.getImageUrl(index));
          final isSelected = index == viewModel.currentIndex;

          return GestureDetector(
            onTap: () {
              viewModel.goToImage(index);
              _animatePageView(index);
            },
            child: Container(
              width: 70,
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? widget.primaryColor : Colors.transparent,
                  width: isSelected ? 3 : 0,
                ),
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: widget.primaryColor.withOpacity(0.3),
                      blurRadius: 6,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[300],
                        child: Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        color: Colors.black.withOpacity(0.2),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Open fullscreen lightbox view
  void _openLightbox(
    BuildContext context,
    ImageCarouselViewModel viewModel,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Image Gallery',
      barrierColor: Colors.black87,
      transitionDuration: Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ImageLightboxWidget(
          gallery: widget.gallery,
          initialIndex: viewModel.currentIndex,
          proxyImageUrl: widget.proxyImageUrl,
          primaryColor: widget.primaryColor,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  /// Animate page view to specific index
  void _animatePageView(int index) {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }
}
