import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';

class NoThumbScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
  
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse};
}

typedef MetadataFetcher = Future<Map<String, String>> Function(String imagePath);

class ImagePreviewPage extends StatefulWidget {
  final List<String> allImagePaths;
  final int initialIndex;
  final MetadataFetcher onGetMetadata;

  const ImagePreviewPage({
    super.key,
    required this.allImagePaths,
    required this.initialIndex,
    required this.onGetMetadata,
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  Map<String, String>? _currentMetadata;
  bool _isLoadingMetadata = false;
  bool _isFullscreen = false;
  bool _showControls = true;
  bool _showMetadataPanel = true;
  final ScrollController _thumbnailScrollController = ScrollController();
  final Map<int, Map<String, String>> _metadataCache = {};
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    
    // INIZIALIZZA PRIMA L'ANIMATION CONTROLLER
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // POI INIZIALIZZA _fadeAnimation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    
    _loadMetadata(widget.allImagePaths[_currentIndex]);
    _animationController.forward();
  }

  Future<void> _loadMetadata(String path) async {
    final cacheKey = widget.allImagePaths.indexOf(path);
    if (_metadataCache.containsKey(cacheKey)) {
      setState(() => _currentMetadata = _metadataCache[cacheKey]);
      return;
    }
    
    setState(() => _isLoadingMetadata = true);

    try {
      final metadata = await widget.onGetMetadata(path);
      _metadataCache[cacheKey] = metadata;
      
      if (mounted) {
        setState(() {
          _currentMetadata = metadata;
          _isLoadingMetadata = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentMetadata = {'Error': 'Impossibile caricare i metadati'};
          _isLoadingMetadata = false;
        });
      }
    }
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
      _loadMetadata(widget.allImagePaths[index]);
      _scrollToCurrentThumbnail();
    }
  }

  void _scrollToCurrentThumbnail() {
    if (_thumbnailScrollController.hasClients) {
      const itemWidth = 80.0;
      final offset = (_currentIndex * itemWidth) - (MediaQuery.of(context).size.width / 2) + (itemWidth / 2);
      
      _thumbnailScrollController.animateTo(
        offset.clamp(0.0, _thumbnailScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _toggleFullscreen() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(!_isFullscreen);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        _isFullscreen ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
    }
    setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<void> _copyToClipboard(String text, String key) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$key copiato!'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    _animationController.dispose();

    if (_isFullscreen) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        windowManager.setFullScreen(false);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 800;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.escape:
              if (_isFullscreen) _toggleFullscreen();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowRight:
              if (_currentIndex < widget.allImagePaths.length - 1) {
                _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
              }
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowLeft:
              if (_currentIndex > 0) {
                _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
              }
              return KeyEventResult.handled;
            case LogicalKeyboardKey.space:
              if (_isFullscreen) setState(() => _showControls = !_showControls);
              return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, _) => Opacity(
          opacity: _fadeAnimation.value,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _isFullscreen ? _buildFullscreenView() : SafeArea(child: 
              isWideScreen ? _buildDesktopLayout() : _buildMobileLayout()
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenView() {
    return MouseRegion(
      onEnter: (_) => setState(() => _showControls = true),
      onExit: (_) => setState(() => _showControls = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.allImagePaths.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: Image.file(
                File(widget.allImagePaths[index]),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 100),
              ),
            ),
          ),
          
          if (_showControls) ...[
            Positioned(
              top: 20, left: 20,
              child: _buildCounter(),
            ),
            Positioned(
              top: 20, right: 20,
              child: _buildIconButton(Icons.close, _toggleFullscreen),
            ),
            if (_currentIndex > 0)
              Positioned(left: 20, top: 0, bottom: 0, child: _buildNavButton(Icons.arrow_back_ios_new, true)),
            if (_currentIndex < widget.allImagePaths.length - 1)
              Positioned(right: 20, top: 0, bottom: 0, child: _buildNavButton(Icons.arrow_forward_ios, false)),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(child: _buildMainImageView()),
        _buildThumbnailCarousel(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.black),
          child: ElevatedButton.icon(
            onPressed: () => _showMetadataBottomSheet(context),
            icon: const Icon(Icons.info_outline, size: 20),
            label: const Text('Metadati'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: _showMetadataPanel ? 3 : 1,
                child: Column(
                  children: [
                    Expanded(child: _buildMainImageView()),
                    _buildThumbnailCarousel(),
                  ],
                ),
              ),
              if (_showMetadataPanel) ...[
                Container(width: 1, color: Colors.grey[800]),
                Expanded(flex: 1, child: _buildMetadataPanel()),
              ] else
                _buildMetadataToggle(),
            ],
          ),
        ),
      ],
    );
  }

Widget _buildMetadataPanel() {
  return Container(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: Colors.grey[800]!)),
    ),
    child: Column(
      children: [
        // Header minimale
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
          ),
          child: Row(
            children: [
              const Text(
                'Metadati',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: IconButton(
                  onPressed: () => setState(() => _showMetadataPanel = false),
                  icon: Icon(Icons.chevron_right, color: Colors.grey[400]),
                  iconSize: 20,
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ),
            ],
          ),
        ),
        // Contenuto
        Expanded(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: _buildMetadataView(),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildMetadataToggle() {
    return MouseRegion(
      onEnter: (_) => setState(() => _showControls = true),
      onExit: (_) => setState(() => _showControls = false),
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 40,
          color: Colors.black,
          child: Center(
            child: _buildIconButton(Icons.chevron_left, () => setState(() => _showMetadataPanel = true)),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildIconButton(Icons.arrow_back, () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              _buildCounter(),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleFullscreen,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue[600]!.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text('Schermo Intero', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[700]!.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_currentIndex + 1} di ${widget.allImagePaths.length}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildMainImageView() {
    return Container(
      color: Colors.black,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.allImagePaths.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => Image.file(
          File(widget.allImagePaths[index]),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.grey[600], size: 80),
                const SizedBox(height: 16),
                Text('Impossibile caricare l\'immagine', style: TextStyle(color: Colors.grey[400])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailCarousel() {
    return ScrollConfiguration(
      behavior: NoThumbScrollBehavior(),
      child: Container(
        height: 100,
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: ListView.builder(
          controller: _thumbnailScrollController,
          scrollDirection: Axis.horizontal,
          itemCount: widget.allImagePaths.length,
          itemBuilder: (context, index) {
            final isSelected = index == _currentIndex;
            final size = isSelected ? 75.0 : 60.0;
            
            return GestureDetector(
              onTap: () => _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.ease),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: size,
                height: size,
                margin: EdgeInsets.symmetric(horizontal: 6, vertical: isSelected ? 0 : 7.5),
                decoration: BoxDecoration(
                  border: Border.all(color: isSelected ? Colors.blue[400]! : Colors.grey[700]!, width: isSelected ? 3 : 1.5),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.blue[400]!.withOpacity(0.5), blurRadius: 12)] : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(widget.allImagePaths[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.error_outline, color: Colors.white38),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavButton(IconData icon, bool isPrevious) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => isPrevious ? _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease) 
                                 : _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  void _showMetadataBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue[400]),
                  const SizedBox(width: 8),
                  const Text('Metadati Immagine', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
              ),
              const Divider(color: Colors.grey),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16), 
                  child: _buildMetadataView(scrollController: scrollController)
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
Widget _buildMetadataView({ScrollController? scrollController}) {
  if (_isLoadingMetadata) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.blue[400]),
          const SizedBox(height: 16),
          const Text('Caricamento metadati...', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  if (_currentMetadata == null || _currentMetadata!.isEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: Colors.grey[600], size: 64),
          const SizedBox(height: 16),
          Text('Nessun metadato disponibile', style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  final metadata = _currentMetadata!;
  final widgets = <Widget>[];

  // DEBUG: Stampa tutto per debugging
  print('=== METADATA DEBUG ===');
  print('Keys: ${metadata.keys.toList()}');
  metadata.forEach((key, value) {
    print('$key: $value');
  });
  print('=====================');

  // Cerca i prompt PRINCIPALI - usa le chiavi esatte dal tuo parser
  final positivePrompt = metadata['Prompt Positive'] ?? '';
  final negativePrompt = metadata['Prompt Negative'] ?? '';
  
  // Fallback: cerca anche altre varianti di chiavi
  final positivePromptAlt = metadata['prompt'] ?? metadata['positive prompt'] ?? '';
  final negativePromptAlt = metadata['negative prompt'] ?? metadata['negative_prompt'] ?? '';

  // Usa i valori principali, se vuoti usa i fallback
  final finalPositivePrompt = positivePrompt.isNotEmpty ? positivePrompt : positivePromptAlt;
  final finalNegativePrompt = negativePrompt.isNotEmpty ? negativePrompt : negativePromptAlt;

  print('🔍 FINAL POSITIVE PROMPT: $finalPositivePrompt');
  print('🔍 FINAL NEGATIVE PROMPT: $finalNegativePrompt');

  if (finalPositivePrompt.isNotEmpty) {
    widgets.add(_buildMetadataEntry('Prompt Positivo', finalPositivePrompt, true, true));
  }
  if (finalNegativePrompt.isNotEmpty) {
    widgets.add(_buildMetadataEntry('Prompt Negativo', finalNegativePrompt, true, false));
  }

  // Aggiungi altri metadati importanti con fallback per diverse chiavi
  final model = metadata['Model'] ?? metadata['model'] ?? '';
  final sampler = metadata['Sampler'] ?? metadata['sampler'] ?? '';
  final steps = metadata['Steps'] ?? metadata['steps'] ?? '';
  final cfgScale = metadata['CFG Scale'] ?? metadata['cfg scale'] ?? metadata['cfg_scale'] ?? '';
  final seed = metadata['Seed'] ?? metadata['seed'] ?? '';

  if (model.isNotEmpty || sampler.isNotEmpty) {
    widgets.add(_buildCombinedEntry('Model / Sampler', model, sampler));
  }
  if (steps.isNotEmpty || cfgScale.isNotEmpty) {
    widgets.add(_buildCombinedEntry('Steps / CFG Scale', steps, cfgScale));
  }
  if (seed.isNotEmpty) {
    widgets.add(_buildMetadataEntry('Seed', seed, false, false));
  }

  // Se non ci sono widget, mostra tutti i metadati
  if (widgets.isEmpty) {
    metadata.forEach((key, value) {
      if (value.isNotEmpty && !key.toLowerCase().contains('hash')) {
        widgets.add(_buildMetadataEntry(key, value, false, false));
      }
    });
  }

  return SingleChildScrollView(
    controller: scrollController,
    child: Column(children: widgets.isEmpty ? [_buildEmptyMetadata()] : widgets),
  );
}
 
  String _findValue(Map<String, String> metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  Widget _buildMetadataEntry(String title, String value, bool isPrompt, bool isPositive) {
    final color = _getEntryColor(isPrompt, isPositive);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_getEntryIcon(isPrompt, isPositive), color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
            _buildCopyButton(value, title),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3), 
              borderRadius: BorderRadius.circular(8)
            ),
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedEntry(String title, String value1, String value2) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.tune, color: Colors.blue[400], size: 18),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: Colors.blue[300], fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          if (value1.isNotEmpty && value2.isNotEmpty)
            Row(children: [
              Expanded(child: _buildCombinedItem('Model', value1)),
              const SizedBox(width: 20),
              Expanded(child: _buildCombinedItem('Sampler', value2)),
            ])
          else if (value1.isNotEmpty)
            _buildCombinedItem(title.split(' / ').first, value1)
          else
            _buildCombinedItem(title.split(' / ').last, value2),
        ],
      ),
    );
  }

  Widget _buildCombinedItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
          const SizedBox(width: 8),
          _buildCopyButton(value, label, small: true),
        ]),
      ],
    );
  }

  Widget _buildCopyButton(String text, String label, {bool small = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _copyToClipboard(text, label),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.all(small ? 6 : 8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Icon(Icons.content_copy, color: Colors.blue[300], size: small ? 14 : 16),
        ),
      ),
    );
  }

  Widget _buildEmptyMetadata() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: Colors.grey[600], size: 48),
          const SizedBox(height: 16),
          Text('Nessun metadato significativo trovato', style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Color _getEntryColor(bool isPrompt, bool isPositive) {
    if (!isPrompt) return Colors.blue;
    return isPositive ? Colors.green : Colors.red;
  }

  IconData _getEntryIcon(bool isPrompt, bool isPositive) {
    if (!isPrompt) return Icons.info_outline;
    return isPositive ? Icons.add_circle : Icons.remove_circle;
  }
}