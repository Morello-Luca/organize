// widgets/optimized_image_card.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_cache_service.dart';
import '../services/image_preload_service.dart';
import 'dart:typed_data'; 


class OptimizedImageCard extends StatefulWidget {
  final String imagePath;
  final bool isSelected;
  final double carouselHeight;
  final VoidCallback? onTap;
  final ImagePreloadService? preloadService;
  final int? imageIndex;

  const OptimizedImageCard({
    super.key,
    required this.imagePath,
    required this.isSelected,
    required this.carouselHeight,
    this.onTap,
    this.preloadService,
    this.imageIndex,
  });

  @override
  State<OptimizedImageCard> createState() => _OptimizedImageCardState();
}

class _OptimizedImageCardState extends State<OptimizedImageCard> {
  final ImageCacheService _cacheService = ImageCacheService();
  Uint8List? _cachedImage;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadCachedImage();
  }

  Future<void> _loadCachedImage() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Verifica se l'immagine è già preloadata
      final isPreloaded = widget.preloadService?.isPreloaded(widget.imagePath) ?? false;
      
      if (isPreloaded) {
        _cachedImage = await _cacheService.getThumbnail(widget.imagePath);
      } else {
        // Caricamento diretto con priorità bassa
        _cachedImage = await _cacheService.getThumbnail(widget.imagePath);
        
        // Registra per preload futuro
        widget.preloadService?.recordImageAccess(widget.imagePath);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading cached image: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageWidth = widget.carouselHeight;
    
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: imageWidth,
        height: widget.carouselHeight,
        decoration: BoxDecoration(
          border: widget.isSelected
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
              : Border.all(color: Colors.grey[300]!, width: 1),
          boxShadow: [
            if (widget.isSelected)
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 12,
                spreadRadius: 2,
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
          ],
        ),
        child: Stack(
          children: [
            // Image content
            if (_isLoading)
              _buildLoadingContent()
            else if (_hasError || _cachedImage == null)
              _buildErrorContent()
            else
              Image.memory(
                _cachedImage!,
                width: imageWidth,
                height: widget.carouselHeight,
                fit: BoxFit.cover,
              ),
            
            // Selection overlay
            if (widget.isSelected)
              Container(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
            
            // Selection badge
            if (widget.isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.grey[400]!,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorContent() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'Unable to load',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}