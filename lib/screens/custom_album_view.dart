import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/album.dart';
import '../models/carousel.dart';
import '../services/storage_service.dart';
import 'image_preview_page.dart';
import '../services/folder_sync_service.dart';
import '../widgets/optimized_image_card.dart';
// 🔥 AGGIUNGI QUESTI IMPORT
import '../services/background_metadata_service.dart';
import '../services/image_preload_service.dart';

class AlbumViewPage extends StatefulWidget {
  final Album album;

  const AlbumViewPage({super.key, required this.album});

  @override
  State<AlbumViewPage> createState() => _AlbumViewPageState();
}

class _AlbumViewPageState extends State<AlbumViewPage> {
  final StorageService _storageService = StorageService();
  Timer? _autosaveTimer;
  static const Duration _autosaveDelay = Duration(seconds: 2);
  
  late List<Carousel> _carousels;
  final _uuid = const Uuid();
  FolderSyncService? _syncService;
  // 🔥 AGGIUNGI PRELOAD SERVICE
  final ImagePreloadService _preloadService = ImagePreloadService();

  bool _isEditMode = false;
  final Set<String> _selectedImages = {};
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _carousels = widget.album.carousels.map((c) => c.copyWith()).toList();
    _initializeSyncService();
    // 🔥 PRELOAD IMMAGINI INIZIALI
    _preloadInitialImages();
  }

  Future<void> _initializeSyncService() async {
    final storage = StorageService();
    final sourcePath = await storage.getSourceFolderPath();
    if (sourcePath != null) {
      _syncService = FolderSyncService(sourceFolderPath: sourcePath);
    }
  }

  // 🔥 NUOVO METODO: PRELOAD IMMAGINI INIZIALI
  void _preloadInitialImages() {
    final allImages = _carousels.expand((c) => c.imagePaths).toList();
    if (allImages.isNotEmpty) {
      _preloadService.preloadInitialSet(allImages);
    }
  }
  
  @override
  void dispose() {
    _autosaveTimer?.cancel();
    // 🔥 DISPOSE PRELOAD SERVICE
    _preloadService.dispose();
    super.dispose();
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true); 
    }
    _scheduleAutosave(); 
  }
  
  // ========== AUTOSAVE LOGIC ==========

  void _scheduleAutosave() {
    if (!_hasChanges) return;
    
    _autosaveTimer?.cancel();
    
    _autosaveTimer = Timer(_autosaveDelay, () async {
      await _performAutosave();
    });
  }

  Future<void> _performAutosave() async {
    if (!mounted || !_hasChanges) return;
    
    final updatedAlbum = widget.album.copyWith(
      carousels: _carousels,
      lastEdited: DateTime.now(),
    );

    try {
      await _storageService.updateAlbum(updatedAlbum);
      
      if (mounted) {
        setState(() {
          _carousels = updatedAlbum.carousels.map((c) => c.copyWith()).toList();
          _hasChanges = false;
        });
      }
    } catch (e) {
      // 🔥 GESTIONE ERRORI MIGLIORATA
      if (mounted) {
        _showSnackBar('Error saving album: ${e.toString()}');
      }
    }
  }

  // ========== METADATA & PREVIEW LOGIC ==========

  void _openImagePreview(List<String> imagePaths, int initialIndex) {
    // 🔥 REGISTRA ACCESSO PER PRELOAD
    _preloadService.recordImageAccess(imagePaths[initialIndex]);
    
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
            ImagePreviewPage(
              allImagePaths: imagePaths,
              initialIndex: initialIndex,
              onGetMetadata: _getMetadataForImagePath, 
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        fullscreenDialog: true,
      ),
    );
  }

  // 🔥 SOSTITUISCI CON BACKGROUND SERVICE - MOLTO PIÙ EFFICIENTE
  Future<Map<String, String>> _getMetadataForImagePath(String path) async {
    try {
      return await BackgroundMetadataService.extractMetadata(path);
    } catch (e) {
      return {'Error': 'Failed to extract metadata: ${e.toString()}'};
    }
  }

  // ========== CAROUSEL OPERATIONS ==========

  Future<void> _addCarousel() async {
    final newCarouselId = _uuid.v4();
    String? carouselFolderPath;
    final carouselName = 'Carousel ${_carousels.length + 1}';
    
    final albumSourceFolder = widget.album.sourceFolder;
    if (_syncService != null && albumSourceFolder != null) {
      try {
        final albumFolderPath = path.join(_syncService!.sourceFolderPath, albumSourceFolder);
        carouselFolderPath = await _syncService!.createFolderForCarousel(albumFolderPath, carouselName);
      } catch (e) {
        // 🔥 GESTIONE ERRORI CREAZIONE CARTELLA
        print('Failed to create carousel folder: $e');
        _showSnackBar('Created carousel but failed to create folder');
      }
    }

    setState(() {
      _carousels.add(Carousel(
        id: newCarouselId,
        title: carouselName,
        imagePaths: [],
        sourceFolder: carouselFolderPath != null 
            ? path.relative(carouselFolderPath, from: _syncService!.sourceFolderPath)
            : null,
      ));
      _markChanged();
    });
  }

  void _deleteCarousel(String carouselId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Carousel'),
        content: const Text('Are you sure you want to delete this carousel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _carousels.removeWhere((c) => c.id == carouselId);
                _markChanged();
              });
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _renameCarousel(String carouselId, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Carousel'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Carousel name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                setState(() {
                  final index = _carousels.indexWhere((c) => c.id == carouselId);
                  if (index != -1) {
                    _carousels[index].title = newTitle;
                    _markChanged();
                  }
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _reorderCarousels(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _carousels.removeAt(oldIndex);
      _carousels.insert(newIndex, item);
      _markChanged();
    });
  }

  // ========== IMAGE OPERATIONS ==========

  Future<void> _importImages() async {
    if (_carousels.isEmpty) {
      _showSnackBar('Create a carousel first');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final selectedCarousel = await showDialog<Carousel>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Carousel',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _carousels.map((carousel) => ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                          ),
                          child: Icon(Icons.view_carousel, color: Colors.blue),
                        ),
                        title: Text(carousel.title),
                        subtitle: Text('${carousel.imagePaths.length} images'),
                        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16),
                        onTap: () => Navigator.pop(ctx, carousel),
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selectedCarousel == null) return;

    setState(() {
      final newPaths = result.files
          .where((f) => f.path != null && f.path!.isNotEmpty)
          .map((f) => f.path!)
          .where((path) => !selectedCarousel.imagePaths.contains(path))
          .toList();

      selectedCarousel.imagePaths.addAll(newPaths);
      _markChanged();
      
      // 🔥 PRELOAD NUOVE IMMAGINI
      _preloadService.preloadInitialSet(newPaths);
    });

    _showSnackBar('${result.files.length} images imported to ${selectedCarousel.title}');
  }

  void _toggleImageSelection(String path) {
    setState(() {
      if (_selectedImages.contains(path)) {
        _selectedImages.remove(path);
      } else {
        _selectedImages.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedImages.clear();
      for (var carousel in _carousels) {
        _selectedImages.addAll(carousel.imagePaths);
      }
    });
  }

  void _deselectAll() {
    setState(() => _selectedImages.clear());
  }

  void _deleteSelectedImages() {
    if (_selectedImages.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Images'),
        content: Text('Delete ${_selectedImages.length} selected images?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                for (var carousel in _carousels) {
                  carousel.imagePaths
                      .removeWhere((path) => _selectedImages.contains(path));
                }
                _selectedImages.clear();
                _markChanged();
              });
              Navigator.pop(ctx);
              _showSnackBar('Images deleted');
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _reorderImages(String carouselId, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final carousel = _carousels.firstWhere((c) => c.id == carouselId);
      final item = carousel.imagePaths.removeAt(oldIndex);
      carousel.imagePaths.insert(newIndex, item);
      _markChanged();
    });
  }

  // ========== SAVE & EXIT ==========

  Future<void> _saveAndExit() async {
    print('💾 _saveAndExit chiamato - hasChanges: $_hasChanges');
    
    _autosaveTimer?.cancel();
    
    final albumToPop = widget.album.copyWith(
      carousels: _carousels,
      lastEdited: DateTime.now(),
    );
    
    print('🔥 SALVATAGGIO FORZATO: ${albumToPop.name} - lastEdited: ${albumToPop.lastEdited}');
    
    try {
      await _storageService.updateAlbum(albumToPop);
      
      if (mounted) {
        print('↩️ TORNO A SETLIST PAGE');
        Navigator.pop(context, albumToPop); 
      }
    } catch (e) {
      // 🔥 GESTIONE ERRORI SALVATAGGIO
      print('❌ ERRORE SALVATAGGIO: $e');
      if (mounted) {
        _showSnackBar('Error saving album: ${e.toString()}');
        // Forza il pop comunque per non bloccare l'utente
        Navigator.pop(context, widget.album);
      }
    }
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, 
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _saveAndExit();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _saveAndExit();
            },
          ),
          title: Row(
            children: [
              Hero(
                tag: 'album-${widget.album.id}',
                child: Text(
                  widget.album.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
              if (_hasChanges) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Unsaved changes', 
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (_isEditMode && _selectedImages.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.deselect),
                onPressed: _deselectAll,
                tooltip: 'Deselect all',
              ),
            if (_isEditMode)
              IconButton(
                icon: const Icon(Icons.select_all),
                onPressed: _selectAll,
                tooltip: 'Select all',
              ),
            Container(
              decoration: BoxDecoration(
                color: _isEditMode 
                    ? Colors.green.withOpacity(0.1)
                    : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  setState(() {
                    _isEditMode = !_isEditMode;
                    if (!_isEditMode) _selectedImages.clear();
                  });
                },
                icon: Icon(
                  _isEditMode ? Icons.check : Icons.edit,
                  color: _isEditMode ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
                label: Text(
                  _isEditMode ? 'Done' : 'Edit',
                  style: TextStyle(
                    color: _isEditMode ? Colors.green : Theme.of(context).colorScheme.primary,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_photo_alternate,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              onPressed: _importImages,
              tooltip: 'Import images',
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: _isEditMode
            ? _selectedImages.isNotEmpty
                ? FloatingActionButton.extended(
                    onPressed: _deleteSelectedImages,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.delete),
                    label: Text('Delete (${_selectedImages.length})'),
                  )
                : null
            : FloatingActionButton.extended(
                onPressed: _addCarousel,
                icon: const Icon(Icons.add),
                label: const Text('New Carousel'),
              ),
        body: _carousels.isEmpty
            ? _buildEmptyState()
            : ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                onReorder: _isEditMode ? _reorderCarousels : (_, __) {},
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _carousels.length,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final carousel = _carousels[index];
                  return _CarouselRow(
                    key: ValueKey(carousel.id),
                    carousel: carousel,
                    carouselIndex: index,
                    isEditMode: _isEditMode,
                    selectedImages: _selectedImages,
                    onImageTap: _toggleImageSelection,
                    onDelete: () => _deleteCarousel(carousel.id),
                    onRename: () => _renameCarousel(carousel.id, carousel.title),
                    onReorderImages: (oldIdx, newIdx) =>
                        _reorderImages(carousel.id, oldIdx, newIdx),
                    onImagePreview: (imagePath, imageIndex) {
                      if (!_isEditMode) {
                        _openImagePreview(carousel.imagePaths, imageIndex);
                      }
                    },
                    // 🔥 PASSA IL PRELOAD SERVICE
                    preloadService: _preloadService,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.view_carousel_outlined,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No carousels yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap the button below to create your first carousel',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _addCarousel,
            icon: const Icon(Icons.add),
            label: const Text('Create Carousel'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CAROUSEL ROW WIDGET - MODIFICATO CON PRELOAD
// ============================================================================

class _CarouselRow extends StatefulWidget {
  final Carousel carousel;
  final int carouselIndex;
  final bool isEditMode;
  final Set<String> selectedImages;
  final Function(String) onImageTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final Function(int, int) onReorderImages;
  final Function(String, int) onImagePreview;
  // 🔥 AGGIUNGI PRELOAD SERVICE
  final ImagePreloadService preloadService;

  const _CarouselRow({
    super.key,
    required this.carousel,
    required this.carouselIndex,
    required this.isEditMode,
    required this.selectedImages,
    required this.onImageTap,
    required this.onDelete,
    required this.onRename,
    required this.onReorderImages,
    required this.onImagePreview,
    required this.preloadService, // 🔥 NUOVO PARAMETRO
  });

  @override
  State<_CarouselRow> createState() => __CarouselRowState();
}

class __CarouselRowState extends State<_CarouselRow> {
  final _scrollController = ScrollController();
  bool _showLeftArrow = false;
  bool _showRightArrow = false;
  bool _isHovering = false;

  double _dragStartX = 0.0;
  bool _isDragging = false;
  int _lastCenterIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateArrows);
    _scrollController.addListener(_handleScrollForPreload); // 🔥 NUOVO LISTENER
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateArrows();
    });
  }

  @override
  void didUpdateWidget(_CarouselRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateArrows();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose(); // 🔥 FIX MEMORY LEAK
    super.dispose();
  }

  void _updateArrows() {
    if (!mounted || !_scrollController.hasClients) return;

    setState(() {
      _showLeftArrow = _scrollController.offset > 10;
      _showRightArrow = _scrollController.offset <
          _scrollController.position.maxScrollExtent - 10;
    });
  }

  // 🔥 NUOVO METODO: PRELOAD BASATO SU SCROLL
  void _handleScrollForPreload() {
    if (!_scrollController.hasClients || widget.carousel.imagePaths.isEmpty) return;
    
    final viewportWidth = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;
    
    // Calcola indice centrale approssimativo
    final centerIndex = (scrollOffset / (150 + 8)).round(); // 150 = image width, 8 = padding
    final clampedIndex = centerIndex.clamp(0, widget.carousel.imagePaths.length - 1);
    
    if (clampedIndex != _lastCenterIndex) {
      _lastCenterIndex = clampedIndex;
      
      // Aggiorna preload service
      widget.preloadService.updateViewport(
        centerIndex: clampedIndex,
        allImages: widget.carousel.imagePaths,
        direction: clampedIndex > _lastCenterIndex 
            ? ScrollDirection.forward 
            : ScrollDirection.backward,
        velocity: 1.0, // Approssimato
      );
    }
  }

  void _scroll(bool forward) {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset + (forward ? 600.0 : -600.0);
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.isEditMode) return;
    
    _isDragging = true;
    _dragStartX = details.globalPosition.dx;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.isEditMode || !_isDragging) return;
    
    final double delta = _dragStartX - details.globalPosition.dx;
    _dragStartX = details.globalPosition.dx;
    
    final double newOffset = _scrollController.offset + delta;
    _scrollController.jumpTo(newOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    ));
  }

  void _handleDragEnd(DragEndDetails details) {
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.carousel.imagePaths;
    final targetHeight = 150.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (widget.isEditMode) 
                  ReorderableDragStartListener(
                    index: widget.carouselIndex,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                        ),
                        child: Icon(
                          Icons.drag_handle, 
                          color: Colors.grey[600], 
                          size: 18
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        widget.carousel.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${images.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isEditMode) ...[
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.orange,
                      ),
                    ),
                    onPressed: widget.onRename,
                    tooltip: 'Rename',
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Colors.red,
                      ),
                    ),
                    onPressed: widget.onDelete,
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 0),

          // Images
          if (images.isEmpty)
            Container(
              height: targetHeight,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No images in this carousel',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            MouseRegion(
              onEnter: (_) => setState(() => _isHovering = true),
              onExit: (_) => setState(() => _isHovering = false),
              child: GestureDetector(
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                child: SizedBox(
                  height: targetHeight,
                  child: Stack(
                    children: [
                      widget.isEditMode
                          ? _buildReorderableList(images, targetHeight)
                          : _buildScrollableList(images, targetHeight),
                      if (!widget.isEditMode && _isHovering && _showLeftArrow)
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _ArrowButton(
                              icon: Icons.chevron_left,
                              onPressed: () => _scroll(false),
                            ),
                          ),
                        ),
                      if (!widget.isEditMode && _isHovering && _showRightArrow)
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _ArrowButton(
                              icon: Icons.chevron_right,
                              onPressed: () => _scroll(true),
                            ),
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

  Widget _buildScrollableList(List<String> images, double carouselHeight) {
    return ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(right: index == images.length - 1 ? 0 : 8),
          child: OptimizedImageCard(
            imagePath: images[index],
            isSelected: false,
            carouselHeight: carouselHeight,
            onTap: () => widget.onImagePreview(images[index], index),
            // 🔥 PASSA INFO PRELOAD
            preloadService: widget.preloadService,
            imageIndex: index,
          ),
        );
      },
    );
  }

  Widget _buildReorderableList(List<String> images, double carouselHeight) {
    return ReorderableListView.builder(
      scrollController: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      onReorder: widget.onReorderImages,
      itemCount: images.length,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 8,
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final imagePath = images[index];
        final isSelected = widget.selectedImages.contains(imagePath);

        return Padding(
          key: ValueKey(imagePath),
          padding: EdgeInsets.only(right: index == images.length - 1 ? 0 : 8),
          child: OptimizedImageCard(
            imagePath: imagePath,
            isSelected: isSelected,
            carouselHeight: carouselHeight,
            onTap: () => widget.onImageTap(imagePath),
            // 🔥 PASSA INFO PRELOAD
            preloadService: widget.preloadService,
            imageIndex: index,
          ),
        );
      },
    );
  }
}

// ============================================================================
// ARROW BUTTON WIDGET (rimane invariato)
// ============================================================================

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ArrowButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87, size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}