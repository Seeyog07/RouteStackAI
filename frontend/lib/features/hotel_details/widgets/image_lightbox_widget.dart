import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/image_carousel_model.dart';
import '../viewmodels/image_carousel_viewmodel.dart';

/// Fullscreen lightbox/image viewer for detailed image viewing
class ImageLightboxWidget extends StatefulWidget {
  final ImageGalleryModel gallery;
  final int initialIndex;
  final String Function(String) proxyImageUrl;
  final Color primaryColor;

  const ImageLightboxWidget({
    Key? key,
    required this.gallery,
    required this.initialIndex,
    required this.proxyImageUrl,
    this.primaryColor = Colors.indigo,
  }) : super(key: key);

  @override
  State<ImageLightboxWidget> createState() => _ImageLightboxWidgetState();
}

class _ImageLightboxWidgetState extends State<ImageLightboxWidget>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  late ImageCarouselViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final vm = ImageCarouselViewModel(widget.gallery);
        vm.goToImage(widget.initialIndex);
        return vm;
      },
      child: Consumer<ImageCarouselViewModel>(
        builder: (context, viewModel, _) {
          _viewModel = viewModel;
          return WillPopScope(
            onWillPop: () async {
              Navigator.of(context).pop();
              return false;
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  // Main image viewer with swipe support
                  _buildImageViewer(viewModel),
                  // Top bar with close button and image info
                  _buildTopBar(context, viewModel),
                  // Bottom bar with navigation and thumbnails
                  _buildBottomBar(viewModel),
                  // Left navigation button
                  if (viewModel.canGoPrevious)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _buildNavButton(
                          onPressed: () {
                            _pageController.previousPage(
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          icon: Icons.chevron_left,
                        ),
                      ),
                    ),
                  // Right navigation button
                  if (viewModel.canGoNext)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _buildNavButton(
                          onPressed: () {
                            _pageController.nextPage(
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          icon: Icons.chevron_right,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Main image viewer with page swipe support
  Widget _buildImageViewer(ImageCarouselViewModel viewModel) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        viewModel.goToImage(index);
      },
      itemCount: widget.gallery.length,
      itemBuilder: (context, index) {
        final imageUrl = widget.proxyImageUrl(
          widget.gallery.getImageUrl(index),
        );

        return GestureDetector(
          onLongPress: () {
            // Add haptic feedback for long press
            HapticFeedback.mediumImpact();
          },
          child: Container(
            color: Colors.black,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withOpacity(0.7),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Failed to load image',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Top bar with close button and image count
  Widget _buildTopBar(
    BuildContext context,
    ImageCarouselViewModel viewModel,
  ) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
            ],
          ),
        ),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.gallery.imageUrls.isNotEmpty ? 'Image Gallery' : '',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                viewModel.getImageCountText(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(width: 12),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom bar with thumbnail strip
  Widget _buildBottomBar(ImageCarouselViewModel viewModel) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black87,
              Colors.transparent,
            ],
          ),
        ),
        padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicator dots
            SingleChildScrollView(
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
                          : Colors.white.withOpacity(0.4),
                      boxShadow: index == viewModel.currentIndex
                          ? [
                              BoxShadow(
                                color: widget.primaryColor.withOpacity(0.5),
                                blurRadius: 6,
                              ),
                            ]
                          : [],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            // Thumbnail strip
            if (widget.gallery.length > 1)
              SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.gallery.length,
                  itemBuilder: (context, index) {
                    final imageUrl = widget.proxyImageUrl(
                      widget.gallery.getImageUrl(index),
                    );
                    final isSelected = index == viewModel.currentIndex;

                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        width: 65,
                        margin: EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? widget.primaryColor
                                : Colors.white.withOpacity(0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Stack(
                            children: [
                              Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) => Container(
                                  color: Colors.grey[800],
                                  child: Icon(
                                    Icons.image,
                                    color: Colors.white30,
                                  ),
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
              ),
          ],
        ),
      ),
    );
  }

  /// Navigation button for lightbox
  Widget _buildNavButton({
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(12),
        child: Icon(
          icon,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}
