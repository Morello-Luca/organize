// services/image_preload_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'image_cache_service.dart';

enum LoadPriority { high, medium, low, none }
enum ScrollDirection { forward, backward, idle }
enum PreloadStrategy { conservative, normal, aggressive }

class PreloadRequest {
  final String imagePath;
  final LoadPriority priority;
  final int positionIndex;
  final DateTime requestedAt;
  final Completer<void>? completer;

  PreloadRequest({
    required this.imagePath,
    required this.priority,
    required this.positionIndex,
    required this.requestedAt,
    this.completer,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreloadRequest &&
          runtimeType == other.runtimeType &&
          imagePath == other.imagePath;

  @override
  int get hashCode => imagePath.hashCode;
}

class ImagePreloadService {
  static final ImagePreloadService _instance = ImagePreloadService._internal();
  factory ImagePreloadService() => _instance;
  
  final ImageCacheService _cacheService = ImageCacheService();
  final List<PreloadRequest> _preloadQueue = [];
  final Map<String, PreloadRequest> _activeRequests = {};
  final Set<String> _completedPreloads = {};
  final Map<String, DateTime> _preloadAccessTimes = {};
  
  static const int _maxConcurrentRequests = 3;
  static const int _maxPreloadAhead = 8;
  static const int _maxPreloadBehind = 2;
  static const int _maxQueueSize = 30;
  static const Duration _cleanupInterval = Duration(seconds: 30);
  
  int _currentCenterIndex = 0;
  ScrollDirection _lastDirection = ScrollDirection.idle;
  double _lastVelocity = 0.0;
  Timer? _cleanupTimer;
  bool _isEnabled = true;

  ImagePreloadService._internal() {
    _startCleanupTimer();
  }

  void updateViewport({
    required int centerIndex,
    required List<String> allImages,
    required ScrollDirection direction,
    required double velocity,
  }) {
    if (!_isEnabled) return;
    
    _currentCenterIndex = centerIndex;
    _lastDirection = direction;
    _lastVelocity = velocity.abs();
    
    _calculateAndSchedulePreloads(allImages);
  }

  Future<void> preloadInitialSet(List<String> imagePaths, {int centerIndex = 0}) async {
    if (!_isEnabled) return;
    
    _currentCenterIndex = centerIndex;
    final strategy = PreloadStrategy.normal;
    final range = _calculatePreloadRange(strategy, imagePaths.length);
    
    for (int i = range.start; i <= range.end; i++) {
      if (i >= 0 && i < imagePaths.length) {
        final imagePath = imagePaths[i];
        if (!_completedPreloads.contains(imagePath)) {
          final priority = _calculatePriorityForIndex(i, range);
          _schedulePreload(imagePath, i, priority);
        }
      }
    }
    
    await _processQueue(force: true);
  }

  void _calculateAndSchedulePreloads(List<String> allImages) {
    if (allImages.isEmpty) return;
    
    final preloadStrategy = _calculatePreloadStrategy();
    _cleanupOldRequests();
    
    final range = _calculatePreloadRange(preloadStrategy, allImages.length);
    _scheduleRangePreloads(allImages, range, preloadStrategy);
    _processQueue();
  }

  PreloadStrategy _calculatePreloadStrategy() {
    final bool isScrollingFast = _lastVelocity > 2.0;
    final bool isScrollingVeryFast = _lastVelocity > 5.0;
    
    if (_lastDirection == ScrollDirection.idle) {
      return PreloadStrategy.conservative;
    } else if (isScrollingVeryFast) {
      return PreloadStrategy.aggressive;
    } else if (isScrollingFast) {
      return PreloadStrategy.normal;
    } else {
      return PreloadStrategy.conservative;
    }
  }

  _PreloadRange _calculatePreloadRange(PreloadStrategy strategy, int totalImages) {
    int ahead, behind;
    
    switch (strategy) {
      case PreloadStrategy.conservative:
        ahead = 3;
        behind = 1;
        break;
      case PreloadStrategy.normal:
        ahead = _maxPreloadAhead;
        behind = _maxPreloadBehind;
        break;
      case PreloadStrategy.aggressive:
        ahead = _maxPreloadAhead + 2;
        behind = _maxPreloadBehind + 1;
        break;
    }
    
    final start = (_currentCenterIndex - behind).clamp(0, totalImages - 1);
    final end = (_currentCenterIndex + ahead).clamp(0, totalImages - 1);
    
    return _PreloadRange(start, end);
  }

  void _scheduleRangePreloads(List<String> allImages, _PreloadRange range, PreloadStrategy strategy) {
    for (int i = range.start; i <= range.end; i++) {
      if (i >= 0 && i < allImages.length) {
        final imagePath = allImages[i];
        if (!_completedPreloads.contains(imagePath) && 
            !_activeRequests.containsKey(imagePath) &&
            !_preloadQueue.any((req) => req.imagePath == imagePath)) {
          
          final priority = _calculatePriorityForIndex(i, range);
          _schedulePreload(imagePath, i, priority);
        }
      }
    }
  }

  LoadPriority _calculatePriorityForIndex(int index, _PreloadRange range) {
    final distanceFromCenter = (index - _currentCenterIndex).abs();
    
    if (distanceFromCenter <= 2) {
      return LoadPriority.high;
    } else if (distanceFromCenter <= 5) {
      return LoadPriority.medium;
    } else {
      return LoadPriority.low;
    }
  }

  void _schedulePreload(String imagePath, int index, LoadPriority priority) {
    final existingIndex = _preloadQueue.indexWhere((req) => req.imagePath == imagePath);
    
    if (existingIndex != -1) {
      final existingRequest = _preloadQueue[existingIndex];
      if (existingRequest.priority.index <= priority.index) {
        return;
      } else {
        _preloadQueue.removeAt(existingIndex);
      }
    }
    
    if (_preloadQueue.length >= _maxQueueSize) {
      _preloadQueue.removeWhere((req) => req.priority == LoadPriority.low);
    }
    
    final request = PreloadRequest(
      imagePath: imagePath,
      priority: priority,
      positionIndex: index,
      requestedAt: DateTime.now(),
    );
    
    _insertByPriority(request);
  }

  void _insertByPriority(PreloadRequest request) {
    final index = _preloadQueue.indexWhere(
      (req) => req.priority.index > request.priority.index
    );
    
    if (index == -1) {
      _preloadQueue.add(request);
    } else {
      _preloadQueue.insert(index, request);
    }
  }

  Future<void> _processQueue({bool force = false}) async {
    if (!_isEnabled) return;
    
    while (_activeRequests.length < _maxConcurrentRequests && _preloadQueue.isNotEmpty) {
      final request = _preloadQueue.removeAt(0);
      
      if (_completedPreloads.contains(request.imagePath)) {
        continue;
      }
      
      _activeRequests[request.imagePath] = request;
      unawaited(_executePreload(request));
    }
  }

  Future<void> _executePreload(PreloadRequest request) async {
    try {
      await _cacheService.getThumbnail(request.imagePath);
      
      _completedPreloads.add(request.imagePath);
      _preloadAccessTimes[request.imagePath] = DateTime.now();
      request.completer?.complete();
      
    } catch (e) {
      print('Preload failed for ${request.imagePath}: $e');
      request.completer?.completeError(e);
    } finally {
      _activeRequests.remove(request.imagePath);
      
      if (_preloadQueue.isNotEmpty) {
        _processQueue();
      }
    }
  }

  void _cleanupOldRequests() {
    final now = DateTime.now();
    final cutoffTime = now.subtract(_cleanupInterval);
    
    _preloadQueue.removeWhere((request) => 
      request.priority == LoadPriority.low && 
      request.requestedAt.isBefore(cutoffTime)
    );
    
    _completedPreloads.removeWhere((imagePath) {
      final lastAccess = _preloadAccessTimes[imagePath];
      if (lastAccess == null) return true;
      return lastAccess.isBefore(cutoffTime);
    });
    
    _preloadAccessTimes.removeWhere((imagePath, lastAccess) => 
      lastAccess.isBefore(cutoffTime)
    );
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanupOldRequests();
    });
  }

  bool isPreloaded(String imagePath) {
    return _completedPreloads.contains(imagePath);
  }

  void recordImageAccess(String imagePath) {
    _preloadAccessTimes[imagePath] = DateTime.now();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      _preloadQueue.clear();
      _activeRequests.clear();
    }
  }

  _PreloadStats getStats() {
    return _PreloadStats(
      queueSize: _preloadQueue.length,
      activeRequests: _activeRequests.length,
      completedPreloads: _completedPreloads.length,
      cacheHits: _completedPreloads.length,
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _preloadQueue.clear();
    _activeRequests.clear();
    _completedPreloads.clear();
    _preloadAccessTimes.clear();
  }
}

class _PreloadRange {
  final int start;
  final int end;
  
  const _PreloadRange(this.start, this.end);
}

class _PreloadStats {
  final int queueSize;
  final int activeRequests;
  final int completedPreloads;
  final int cacheHits;
  
  const _PreloadStats({
    required this.queueSize,
    required this.activeRequests,
    required this.completedPreloads,
    required this.cacheHits,
  });
  
  @override
  String toString() {
    return 'PreloadStats(queue: $queueSize, active: $activeRequests, completed: $completedPreloads, hits: $cacheHits)';
  }
}