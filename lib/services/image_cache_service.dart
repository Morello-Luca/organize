// services/image_cache_service.dart - VERSIONE IBRIDA CORRETTA
import 'dart:async'; // 🔥 AGGIUNGI QUESTO IMPORT
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  final Map<String, Uint8List> _memoryCache = {};
  static const int _maxMemoryItems = 150;

  Directory? _cacheDir;
  static const String _thumbnailPrefix = 'thumb_';
  static const String _hqThumbnailPrefix = 'hq_thumb_';
  
  static const int _fastThumbnailSize = 300;
  static const int _hqThumbnailSize = 600;
  static const int _jpegQuality = 92;

  Future<void> initialize() async {
    if (_cacheDir != null) return;
    
    final directory = await getTemporaryDirectory();
    _cacheDir = Directory('${directory.path}/image_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  Future<Uint8List?> getThumbnail(String imagePath, {bool preloadHQ = true}) async {
    await initialize();
    
    final fastKey = '${_thumbnailPrefix}${_getCacheKey(imagePath)}';
    
    if (_memoryCache.containsKey(fastKey)) {
      if (preloadHQ) {
        unawaited(_preloadHighQualityThumbnail(imagePath)); // ✅ ORA FUNZIONA
      }
      return _memoryCache[fastKey];
    }
    
    final fastDiskFile = File('${_cacheDir!.path}/$fastKey');
    if (await fastDiskFile.exists()) {
      final bytes = await fastDiskFile.readAsBytes();
      _addToMemoryCache(fastKey, bytes);
      
      if (preloadHQ) {
        unawaited(_preloadHighQualityThumbnail(imagePath)); // ✅ ORA FUNZIONA
      }
      return bytes;
    }
    
    final fastThumbnail = await _generateThumbnail(imagePath, _fastThumbnailSize, fastKey);
    
    if (preloadHQ && fastThumbnail != null) {
      unawaited(_preloadHighQualityThumbnail(imagePath)); // ✅ ORA FUNZIONA
    }
    
    return fastThumbnail;
  }

  Future<Uint8List?> getHighQualityThumbnail(String imagePath) async {
    await initialize();
    
    final hqKey = '${_hqThumbnailPrefix}${_getCacheKey(imagePath)}';
    
    if (_memoryCache.containsKey(hqKey)) {
      return _memoryCache[hqKey];
    }
    
    final hqDiskFile = File('${_cacheDir!.path}/$hqKey');
    if (await hqDiskFile.exists()) {
      final bytes = await hqDiskFile.readAsBytes();
      _addToMemoryCache(hqKey, bytes);
      return bytes;
    }
    
    return await _generateThumbnail(imagePath, _hqThumbnailSize, hqKey);
  }

  Future<void> _preloadHighQualityThumbnail(String imagePath) async {
    try {
      final hqKey = '${_hqThumbnailPrefix}${_getCacheKey(imagePath)}';
      final hqDiskFile = File('${_cacheDir!.path}/$hqKey');
      
      if (!await hqDiskFile.exists()) {
        await _generateThumbnail(imagePath, _hqThumbnailSize, hqKey);
      }
    } catch (e) {
      print('Background HQ preload failed for $imagePath: $e');
    }
  }

  Future<Uint8List?> _generateThumbnail(String imagePath, int size, String cacheKey) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      
      final resizedImage = _resizeImageWithQuality(image, size);
      final jpegBytes = img.encodeJpg(resizedImage, quality: _jpegQuality);
      final resultBytes = Uint8List.fromList(jpegBytes);
      
      await _saveToDisk(cacheKey, resultBytes);
      _addToMemoryCache(cacheKey, resultBytes);
      
      return resultBytes;
    } catch (e) {
      print('Error generating thumbnail for $imagePath: $e');
      return null;
    }
  }

  img.Image _resizeImageWithQuality(img.Image image, int maxSize) {
    if (image.width <= maxSize && image.height <= maxSize) {
      return image;
    }
    
    final double aspectRatio = image.width / image.height;
    int newWidth, newHeight;
    
    if (aspectRatio > 1) {
      newWidth = maxSize;
      newHeight = (maxSize / aspectRatio).round();
    } else {
      newHeight = maxSize;
      newWidth = (maxSize * aspectRatio).round();
    }
    
    return img.copyResize(
      image, 
      width: newWidth, 
      height: newHeight,
      interpolation: img.Interpolation.average
    );
  }

  Future<void> _saveToDisk(String cacheKey, Uint8List bytes) async {
    try {
      final diskFile = File('${_cacheDir!.path}/$cacheKey');
      await diskFile.writeAsBytes(bytes);
    } catch (e) {
      print('Error saving to disk cache: $e');
    }
  }

  String _getCacheKey(String path) {
    try {
      final file = File(path);
      final stat = file.statSync();
      return '${path.hashCode}_${stat.modified.millisecondsSinceEpoch}';
    } catch (e) {
      return '${path.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    if (_memoryCache.length >= _maxMemoryItems) {
      final firstKey = _memoryCache.keys.first;
      _memoryCache.remove(firstKey);
    }
    _memoryCache[key] = bytes;
  }

  Future<void> upgradeToHighQuality(String imagePath) async {
    await getHighQualityThumbnail(imagePath);
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  Future<void> clearDiskCache() async {
    await initialize();
    if (await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create();
    }
  }
}