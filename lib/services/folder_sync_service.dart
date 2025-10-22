// services/folder_sync_service.dart
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart'; // <-- AGGIUNGI QUESTO
import '../models/album.dart';
import '../models/carousel.dart';
import '../models/sync_state.dart';

class FolderSyncService {
  final String sourceFolderPath;
  final Uuid _uuid = const Uuid(); // <-- AGGIUNGI QUESTO

  FolderSyncService({required this.sourceFolderPath});

  // === SCANSIONE RICORSIVA CARTELLE ===
  Future<Map<String, List<String>>> scanFolderStructure() async {
    final folderImages = <String, List<String>>{};
    
    await _scanDirectoryRecursive(Directory(sourceFolderPath), folderImages);
    return folderImages;
  }

  Future<void> _scanDirectoryRecursive(
      Directory dir, 
      Map<String, List<String>> folderImages,
      [String relativePath = '']) async {
    try {
      final entities = dir.listSync(recursive: false);
      
      final images = <String>[];
      
      for (final entity in entities) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (['.png', '.jpg', '.jpeg', '.webp'].contains(ext)) {
            images.add(entity.path);
          }
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          final newRelativePath = relativePath.isEmpty ? dirName : '$relativePath/$dirName';
          await _scanDirectoryRecursive(entity, folderImages, newRelativePath);
        }
      }
      
      if (images.isNotEmpty) {
        folderImages[relativePath.isEmpty ? 'Root' : relativePath] = images;
      }
    } catch (e) {
      print('❌ Errore scansione cartella ${dir.path}: $e');
    }
  }

  // === CREAZIONE ALBUM DA CARTELLE ESISTENTI ===
// services/folder_sync_service.dart - MODIFICA createAlbumsFromFolders
Future<List<Album>> createAlbumsFromFolders() async {
  final folderImages = await scanFolderStructure();
  final albums = <Album>[];

  for (final entry in folderImages.entries) {
    final folderPath = entry.key;
    final imagePaths = entry.value;

    // Skip root folder
    if (folderPath == 'Root') continue;

    final pathParts = folderPath.split('/');
    
    if (pathParts.length == 1) {
      // Cartella principale → Album
      final album = Album(
        id: _uuid.v4(),
        name: _formatFolderName(folderPath),
        imagePaths: [], // Album principale senza immagini dirette
        carousels: [], // I caroselli verranno aggiunti dopo
        sourceFolder: folderPath,
        createdAt: DateTime.now(),
        lastEdited: DateTime.now(),
      );
      albums.add(album);
    }
  }

  // Ora aggiungi i caroselli per le sottocartelle
  for (final album in albums) {
    if (album.sourceFolder != null) {
      final carousels = _createCarouselsForAlbum(album.sourceFolder!, folderImages);
      album.carousels.addAll(carousels);
    }
  }

  return albums;
}

List<Carousel> _createCarouselsForAlbum(String albumFolder, Map<String, List<String>> folderImages) {
  final carousels = <Carousel>[];
  
  for (final entry in folderImages.entries) {
    final folderPath = entry.key;
    final imagePaths = entry.value;
    
    // Se la cartella è una sottocartella dell'album principale
    if (folderPath.startsWith('$albumFolder/')) {
      final subfolderName = folderPath.substring(albumFolder.length + 1);
      final carousel = Carousel(
        id: _uuid.v4(),
        title: _formatCarouselName(subfolderName),
        imagePaths: imagePaths,
        sourceFolder: folderPath,
      );
      carousels.add(carousel);
    }
    
    // Se è esattamente la cartella dell'album e ha immagini
    else if (folderPath == albumFolder && imagePaths.isNotEmpty) {
      final carousel = Carousel(
        id: _uuid.v4(),
        title: 'Principale',
        imagePaths: imagePaths,
        sourceFolder: folderPath,
      );
      carousels.add(carousel);
    }
  }
  
  return carousels;
}

String _formatCarouselName(String folderName) {
  // Convert "2025" in "2025" mantenendo il nome originale
  return folderName.split('/').last;
}
  String _formatFolderName(String folderPath) {
    // Convert "vacanze/2025" in "Vacanze 2025"
    return folderPath.split('/').map((part) {
      if (part.isEmpty) return part;
      return part[0].toUpperCase() + part.substring(1);
    }).join(' / ');
  }

  // === CREAZIONE CARTELLA PER NUOVO ALBUM ===
// services/folder_sync_service.dart - MODIFICA createFolderForAlbum
Future<String> createFolderForAlbum(String albumName) async {
  final safeName = _sanitizeFolderName(albumName);
  final albumFolder = Directory(path.join(sourceFolderPath, safeName));
  
  if (!await albumFolder.exists()) {
    await albumFolder.create(recursive: true);
    print('✅ Cartella creata: ${albumFolder.path}');
  } else {
    print('ℹ️ Cartella già esistente: ${albumFolder.path}');
  }
  
  return albumFolder.path;
}

// AGGIUNGI metodo per creare sottocartella per carosello
Future<String> createFolderForCarousel(String albumFolderPath, String carouselName) async {
  final safeName = _sanitizeFolderName(carouselName);
  final carouselFolder = Directory(path.join(albumFolderPath, safeName));
  
  if (!await carouselFolder.exists()) {
    await carouselFolder.create(recursive: true);
    print('✅ Sottocartella carosello creata: ${carouselFolder.path}');
  }
  
  return carouselFolder.path;
}
  String _sanitizeFolderName(String name) {
    // Rimuovi caratteri non validi per i path
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  // === SINCRONIZZAZIONE AUTOMATICA ===
// services/folder_sync_service.dart - MODIFICA syncAlbums
Future<SyncResult> syncAlbums(List<Album> existingAlbums) async {
  final folderImages = await scanFolderStructure();
  final updatedAlbums = <Album>[];
  final unassignedImages = <String>[];
  int totalAssigned = 0;

  // 1. Aggiorna percorsi per album e caroselli esistenti
  for (final album in existingAlbums) {
    final updatedCarousels = <Carousel>[];
    
    for (final carousel in album.carousels) {
      final updatedPaths = <String>[];
      
      for (final imagePath in carousel.imagePaths) {
        final newPath = await _findUpdatedImagePath(imagePath);
        if (newPath != null && await File(newPath).exists()) {
          updatedPaths.add(newPath);
          totalAssigned++;
        }
      }
      
      if (updatedPaths.isNotEmpty) {
        updatedCarousels.add(carousel.copyWith(imagePaths: updatedPaths));
      } else {
        updatedCarousels.add(carousel);
      }
    }
    
    if (updatedCarousels.isNotEmpty) {
      updatedAlbums.add(album.copyWith(carousels: updatedCarousels));
    }
  }

  // 2. Trova immagini non assegnate (non in nessun carosello)
  final allAssignedPaths = existingAlbums
      .expand((a) => a.carousels)
      .expand((c) => c.imagePaths)
      .toSet();
  
  for (final images in folderImages.values) {
    for (final imagePath in images) {
      if (!allAssignedPaths.contains(imagePath)) {
        unassignedImages.add(imagePath);
      }
    }
  }

  return SyncResult(
    updatedAlbums: updatedAlbums,
    unassignedImages: unassignedImages,
    totalAssigned: totalAssigned,
    totalUnassigned: unassignedImages.length,
  );
}

  Future<String?> _findUpdatedImagePath(String oldPath) async {
    final fileName = path.basename(oldPath);
    
    // Cerca il file in tutta la struttura
    final foundFiles = await _findFileInStructure(fileName);
    return foundFiles.isNotEmpty ? foundFiles.first : null;
  }

  Future<List<String>> _findFileInStructure(String fileName) async {
    final found = <String>[];
    
    await for (final entity in Directory(sourceFolderPath).list(recursive: true)) {
      if (entity is File && path.basename(entity.path) == fileName) {
        found.add(entity.path);
      }
    }
    
    return found;
  }
}

class SyncResult {
  final List<Album> updatedAlbums;
  final List<String> unassignedImages;
  final int totalAssigned;
  final int totalUnassigned;

  SyncResult({
    required this.updatedAlbums,
    required this.unassignedImages,
    required this.totalAssigned,
    required this.totalUnassigned,
  });
}