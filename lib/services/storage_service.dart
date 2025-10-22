import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album.dart';
import '../models/sync_state.dart';

class StorageService {
  static const _sourceFolderKey = 'source_folder_path';
  static const _jsonFolderKey = 'json_folder_path';
  
  // ========== CHIAVI ORIGINALI PER COMPATIBILITÀ ==========
  static const _albumsKey = 'albums';
  static const _syncStateKey = 'sync_state';

  // ========== CONFIGURAZIONI MULTIPLE ==========
  static const _currentConfigKey = 'current_config';
  static const _availableConfigsKey = 'available_configs';

  // ========== ASPECT RATIO ==========
  static const _defaultAspectRatioKey = 'default_aspect_ratio';

  // ========== CHIAVI DINAMICHE PER CONFIGURAZIONE ==========
  String _getAlbumsKeyForConfig(String configName) {
    return 'albums_$configName';
  }

  String _getSyncStateKeyForConfig(String configName) {
    return 'sync_state_$configName';
  }

  // ========== MIGRAZIONE DATI ESISTENTI ==========
  Future<void> migrateExistingData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Verifica se esistono dati con la vecchia chiave albums
    final oldAlbumsJson = prefs.getString(_albumsKey);
    if (oldAlbumsJson != null) {
      // Migra alla configurazione 'default'
      await prefs.setString(_getAlbumsKeyForConfig('default'), oldAlbumsJson);
      await prefs.remove(_albumsKey); // Rimuovi la vecchia chiave
      print('✅ Dati albums migrati alla configurazione default');
    }
    
    // Verifica se esistono dati con la vecchia chiave sync_state
    final oldSyncStateJson = prefs.getString(_syncStateKey);
    if (oldSyncStateJson != null) {
      await prefs.setString(_getSyncStateKeyForConfig('default'), oldSyncStateJson);
      await prefs.remove(_syncStateKey);
      print('✅ SyncState migrato alla configurazione default');
    }
  }

  // ========== SOURCE FOLDER VALIDATION ==========
  Future<Map<String, dynamic>> getSourceFolderInfo(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return {'isValid': false, 'message': 'Cartella non esistente'};
      }

      final contents = await dir.list().toList();
      final imageFiles = contents.where((entity) {
        if (entity is File) {
          final ext = entity.path.toLowerCase().split('.').last;
          return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
        }
        return false;
      }).toList();

      final subfolders = contents.where((entity) => entity is Directory).toList();

      return {
        'isValid': true,
        'totalImages': imageFiles.length,
        'subfolders': subfolders.length,
        'message': 'Trovate ${imageFiles.length} immagini e ${subfolders.length} cartelle'
      };
    } catch (e) {
      return {'isValid': false, 'message': 'Errore: $e'};
    }
  }

  Future<bool> isSourceFolderValid(String path) async {
    try {
      final dir = Directory(path);
      return await dir.exists();
    } catch (e) {
      return false;
    }
  }

  // ========== ASPECT RATIO METHODS ==========
  Future<String> getDefaultAspectRatio() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultAspectRatioKey) ?? '19:13';
  }

  Future<void> setDefaultAspectRatio(String aspectRatio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultAspectRatioKey, aspectRatio);
  }

  // ========== SYNC STATE METHODS ==========
  Future<SyncState?> getSyncState([String? configName]) async {
    final currentConfig = configName ?? await getCurrentConfig();
    final prefs = await SharedPreferences.getInstance();
    final syncStateKey = _getSyncStateKeyForConfig(currentConfig);
    final syncJson = prefs.getString(syncStateKey);
    if (syncJson == null) return null;
    
    try {
      final decoded = jsonDecode(syncJson);
      return SyncState(
        lastSync: DateTime.parse(decoded['lastSync']),
        totalImages: decoded['totalImages'],
        assignedImages: decoded['assignedImages'],
        unassignedImages: decoded['unassignedImages'],
        folderAlbums: List<String>.from(decoded['folderAlbums']),
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> saveSyncState(SyncState syncState, [String? configName]) async {
    final currentConfig = configName ?? await getCurrentConfig();
    final prefs = await SharedPreferences.getInstance();
    final syncStateKey = _getSyncStateKeyForConfig(currentConfig);
    final encoded = jsonEncode({
      'lastSync': syncState.lastSync.toIso8601String(),
      'totalImages': syncState.totalImages,
      'assignedImages': syncState.assignedImages,
      'unassignedImages': syncState.unassignedImages,
      'folderAlbums': syncState.folderAlbums,
    });
    await prefs.setString(syncStateKey, encoded);
  }

  // ========== CONFIGURATION MANAGEMENT ==========
  Future<String> getCurrentConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentConfigKey) ?? 'default';
  }

  Future<void> setCurrentConfig(String configName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentConfigKey, configName);
  }

  Future<List<String>> getAvailableConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getStringList(_availableConfigsKey);
    return configsJson ?? ['default'];
  }

  Future<void> addConfig(String configName) async {
    final prefs = await SharedPreferences.getInstance();
    final currentConfigs = await getAvailableConfigs();
    
    if (!currentConfigs.contains(configName)) {
      currentConfigs.add(configName);
      await prefs.setStringList(_availableConfigsKey, currentConfigs);
    }
  }

  Future<void> removeConfig(String configName) async {
    final prefs = await SharedPreferences.getInstance();
    final currentConfigs = await getAvailableConfigs();
    
    currentConfigs.remove(configName);
    await prefs.setStringList(_availableConfigsKey, currentConfigs);
    
    // Se era la configurazione corrente, passa a 'default'
    final current = await getCurrentConfig();
    if (current == configName) {
      await setCurrentConfig('default');
    }

    // Rimuovi anche i dati SharedPreferences per questa configurazione
    await prefs.remove(_getAlbumsKeyForConfig(configName));
    await prefs.remove(_getSyncStateKeyForConfig(configName));
  }

  // ========== CREAZIONE CONFIGURAZIONE VUOTA ==========
  Future<void> createEmptyConfig(String configName) async {
    final jsonPath = await getJsonFilePathForConfig(configName);
    if (jsonPath == null) return;

    try {
      final file = File(jsonPath);
      final encoded = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'config': configName,
        'albums': [],
      });
      
      await file.writeAsString(encoded);
      print('✅ Configurazione vuota creata: $configName');
    } catch (e) {
      print('❌ Errore creazione configurazione vuota: $e');
    }
  }

  // ========== SOURCE FOLDER ==========
  Future<String?> getSourceFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceFolderKey);
  }

  Future<void> setSourceFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceFolderKey, path);
  }

  // ========== JSON FOLDER ==========
  Future<String?> getJsonFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_jsonFolderKey);
  }

  Future<void> setJsonFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jsonFolderKey, path);
  }

  // ========== JSON FILE PATHS WITH CONFIG SUPPORT ==========
  Future<String?> getJsonFilePathForConfig([String? configName]) async {
    final jsonFolder = await getJsonFolderPath();
    if (jsonFolder == null) return null;
    
    final currentConfig = configName ?? await getCurrentConfig();
    final fileName = currentConfig == 'default' ? 'albums_data.json' : 'albums_data_$currentConfig.json';
    return '$jsonFolder/$fileName';
  }

  // Metodo legacy per compatibilità
  Future<String?> getJsonFilePath() async {
    return getJsonFilePathForConfig();
  }

  Future<bool> configHasJsonFile(String configName) async {
    final jsonPath = await getJsonFilePathForConfig(configName);
    if (jsonPath == null) return false;
    
    final file = File(jsonPath);
    return await file.exists();
  }

  // ========== BACKUP AUTOMATICO AL JSON ==========
  Future<void> backupAlbumsToJson(List<Album> albums, [String? configName]) async {
    final jsonPath = await getJsonFilePathForConfig(configName);
    if (jsonPath == null) {
      print('⚠️ Nessuna cartella JSON configurata per il backup');
      return;
    }

    try {
      final currentConfig = configName ?? await getCurrentConfig();
      final encoded = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'config': currentConfig,
        'albums': albums.map((a) => a.toJson()).toList(),
      });
      
      final file = File(jsonPath);
      await file.writeAsString(encoded);
      print('✅ Backup completato: $jsonPath');
    } catch (e) {
      print('❌ Errore backup JSON: $e');
    }
  }

  // ========== CARICAMENTO DA JSON ==========
  Future<List<Album>> loadAlbumsFromJson([String? configName]) async {
    final jsonPath = await getJsonFilePathForConfig(configName);
    if (jsonPath == null) {
      print('⚠️ Nessuna cartella JSON configurata per il caricamento');
      return [];
    }

    try {
      final file = File(jsonPath);
      if (!await file.exists()) {
        print('⚠️ File JSON non trovato: $jsonPath');
        return [];
      }

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      
      if (decoded is Map && decoded.containsKey('albums')) {
        final List<dynamic> albumsJson = decoded['albums'];
        return albumsJson.map((json) => Album.fromJson(json)).toList();
      }
      
      return [];
    } catch (e) {
      print('❌ Errore caricamento JSON: $e');
      return [];
    }
  }

  // ========== ALBUMS MANAGEMENT CONFIG-AWARE ==========
  Future<List<Album>> getAlbums([String? configName]) async {
    final currentConfig = configName ?? await getCurrentConfig();
    final prefs = await SharedPreferences.getInstance();
    final albumsKey = _getAlbumsKeyForConfig(currentConfig);
    final albumsJson = prefs.getString(albumsKey);
    if (albumsJson == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(albumsJson);
      return decoded.map((json) => Album.fromJson(json)).toList();
    } catch (e) {
      print('Error loading albums: $e');
      return [];
    }
  }

  Future<void> saveAlbums(List<Album> albums, [String? configName]) async {
    final currentConfig = configName ?? await getCurrentConfig();
    final prefs = await SharedPreferences.getInstance();
    final albumsKey = _getAlbumsKeyForConfig(currentConfig);
    final encoded = jsonEncode(albums.map((a) => a.toJson()).toList());
    await prefs.setString(albumsKey, encoded);
    
    // Backup automatico al JSON per la configurazione corrente
    await backupAlbumsToJson(albums, configName);
  }

  // ========== SINGLE ALBUM UPDATE ==========
  Future<void> updateAlbum(Album updatedAlbum, [String? configName]) async {
    final albums = await getAlbums(configName);
    final index = albums.indexWhere((a) => a.id == updatedAlbum.id);
    
    if (index != -1) {
      albums[index] = updatedAlbum;
      await saveAlbums(albums, configName);
      print('✅ Album updated: ${updatedAlbum.name} with ${updatedAlbum.carousels.length} carousels');
    } else {
      print('⚠️ Album not found for update: ${updatedAlbum.id}');
    }
  }

  // ========== CARICAMENTO INTELLIGENTE CON FALLBACK ==========
  Future<List<Album>> loadAlbumsWithFallback() async {
    final currentConfig = await getCurrentConfig();
    final hasJson = await configHasJsonFile(currentConfig);
    
    if (hasJson) {
      // Carica dal JSON della configurazione corrente
      final jsonAlbums = await loadAlbumsFromJson(currentConfig);
      
      // Se il JSON contiene album, aggiorna SharedPreferences e ritorna
      if (jsonAlbums.isNotEmpty) {
        await saveAlbums(jsonAlbums, currentConfig);
        print('✅ Caricato da JSON ($currentConfig): ${jsonAlbums.length} album');
        return jsonAlbums;
      } else {
        // Se il JSON è vuoto, salva lista vuota in SharedPreferences
        await saveAlbums([], currentConfig);
        print('🔄 Configurazione vuota, SharedPreferences aggiornato');
        return [];
      }
    } else {
      print('ℹ️ Nessun file JSON trovato per la configurazione: $currentConfig');
    }
    
    // Fallback: carica da SharedPreferences CON LA CHIAVE CORRETTA
    final prefsAlbums = await getAlbums(currentConfig);
    print('ℹ️ Caricato da SharedPreferences ($currentConfig): ${prefsAlbums.length} album');
    return prefsAlbums;
  }

  // ========== HELPER: GET SINGLE ALBUM ==========
  Future<Album?> getAlbumById(String albumId, [String? configName]) async {
    final albums = await getAlbums(configName);
    try {
      return albums.firstWhere((a) => a.id == albumId);
    } catch (e) {
      return null;
    }
  }

  // ========== VERIFICA STATO SINCRONIZZAZIONE ==========
  Future<bool> isSourceFolderSynchronized() async {
    final sourcePath = await getSourceFolderPath();
    final jsonPath = await getJsonFolderPath();
    
    // Verifica se entrambi i percorsi sono configurati
    if (sourcePath == null || jsonPath == null) {
      return false;
    }
    
    // Verifica se il file JSON esiste e contiene dati
    try {
      final currentConfig = await getCurrentConfig();
      final jsonFilePath = await getJsonFilePathForConfig(currentConfig);
      if (jsonFilePath == null) return false;
      
      final file = File(jsonFilePath);
      if (!await file.exists()) {
        return false;
      }
      
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      return decoded is Map && decoded.containsKey('albums');
    } catch (e) {
      return false;
    }
  }

  // ========== SINCRONIZZAZIONE MANUALE ==========
  Future<void> synchronizeData({bool forceJson = false}) async {
    try {
      final currentConfig = await getCurrentConfig();
      final jsonAlbums = await loadAlbumsFromJson(currentConfig);
      final currentAlbums = await getAlbums(currentConfig);
      
      if (forceJson || jsonAlbums.isNotEmpty) {
        // Prioritizza il JSON se forzato o se contiene dati
        await saveAlbums(jsonAlbums, currentConfig);
        print('✅ Sincronizzato da JSON ($currentConfig): ${jsonAlbums.length} album');
      } else if (currentAlbums.isNotEmpty) {
        // Altrimenti esporta i dati correnti
        await backupAlbumsToJson(currentAlbums, currentConfig);
        print('✅ Dati esportati nel JSON ($currentConfig): ${currentAlbums.length} album');
      } else {
        print('ℹ️ Nessun dato da sincronizzare');
      }
    } catch (e) {
      print('❌ Errore durante la sincronizzazione: $e');
    }
  }

  // ========== SWITCH CONFIGURATION ==========
  Future<void> switchConfiguration(String configName) async {
    final currentConfig = await getCurrentConfig();
    
    // Salva i dati correnti prima di cambiare
    final currentAlbums = await getAlbums(currentConfig);
    if (currentAlbums.isNotEmpty) {
      await backupAlbumsToJson(currentAlbums, currentConfig);
    }
    
    // Cambia configurazione
    await setCurrentConfig(configName);
    
    // Se è una nuova configurazione senza file JSON, creane uno vuoto
    final hasJson = await configHasJsonFile(configName);
    if (!hasJson) {
      await createEmptyConfig(configName);
    }
    
    // Carica i dati della nuova configurazione
    final newAlbums = await loadAlbumsWithFallback();
    print('✅ Configurazione cambiata: $currentConfig → $configName (${newAlbums.length} album)');
  }

  // ========== BACKUP MULTIPLE CONFIGURATIONS ==========
  Future<void> backupAllConfigurations() async {
    final configs = await getAvailableConfigs();
    final currentConfig = await getCurrentConfig();
    
    for (final config in configs) {
      final configAlbums = await getAlbums(config);
      if (configAlbums.isNotEmpty) {
        await backupAlbumsToJson(configAlbums, config);
      } else {
        // Per configurazioni vuote, crea file JSON vuoto
        await createEmptyConfig(config);
      }
    }
    
    print('✅ Backup completato per tutte le configurazioni: ${configs.length} configs');
  }

  // ========== RESET SINGOLA CONFIGURAZIONE ==========
  Future<void> resetConfig(String configName) async {
    final currentConfig = await getCurrentConfig();
    
    // Pulisci SharedPreferences per questa configurazione
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getAlbumsKeyForConfig(configName));
    await prefs.remove(_getSyncStateKeyForConfig(configName));
    
    // Ricrea il file JSON vuoto
    await createEmptyConfig(configName);
    
    // Se stiamo resettando la configurazione corrente, ricarica i dati vuoti
    if (currentConfig == configName) {
      await loadAlbumsWithFallback();
    }
    
    print('✅ Configurazione resettata: $configName');
  }

  // ========== RESET DATI COMPLETO ==========
  Future<void> resetAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final configs = await getAvailableConfigs();
    
    // Cancella tutti i dati SharedPreferences per tutte le configurazioni
    for (final config in configs) {
      await prefs.remove(_getAlbumsKeyForConfig(config));
      await prefs.remove(_getSyncStateKeyForConfig(config));
    }
    
    // Cancella anche le chiavi globali
    await prefs.remove(_sourceFolderKey);
    await prefs.remove(_jsonFolderKey);
    await prefs.remove(_currentConfigKey);
    await prefs.remove(_availableConfigsKey);
    await prefs.remove(_defaultAspectRatioKey);
    
    // Cancella anche tutti i file JSON delle configurazioni
    try {
      final jsonFolder = await getJsonFolderPath();
      if (jsonFolder != null) {
        final folder = Directory(jsonFolder);
        if (await folder.exists()) {
          final files = await folder.list().toList();
          for (final file in files) {
            if (file is File && file.path.endsWith('.json')) {
              await file.delete();
            }
          }
        }
      }
    } catch (e) {
      print('Errore durante la cancellazione dei file JSON: $e');
    }
    
    // Reimposta la configurazione default
    await prefs.setString(_currentConfigKey, 'default');
    await prefs.setStringList(_availableConfigsKey, ['default']);
    
    print('✅ Tutti i dati sono stati resettati');
  }

  // ========== IMPORT/EXPORT SINGLE CONFIG ==========
  Future<bool> exportConfiguration(String configName, String exportPath) async {
    try {
      final albums = await getAlbums(configName);
      if (albums.isEmpty) {
        // Se non ci sono dati in SharedPreferences, prova a caricare dal JSON
        final jsonAlbums = await loadAlbumsFromJson(configName);
        if (jsonAlbums.isEmpty) return false;
        
        final encoded = jsonEncode({
          'timestamp': DateTime.now().toIso8601String(),
          'config': configName,
          'albums': jsonAlbums.map((a) => a.toJson()).toList(),
        });
        
        final file = File(exportPath);
        await file.writeAsString(encoded);
      } else {
        final encoded = jsonEncode({
          'timestamp': DateTime.now().toIso8601String(),
          'config': configName,
          'albums': albums.map((a) => a.toJson()).toList(),
        });
        
        final file = File(exportPath);
        await file.writeAsString(encoded);
      }
      
      print('✅ Configurazione "$configName" esportata in: $exportPath');
      return true;
    } catch (e) {
      print('❌ Errore esportazione configurazione: $e');
      return false;
    }
  }

  Future<bool> importConfiguration(String configName, String importPath) async {
    try {
      final file = File(importPath);
      if (!await file.exists()) return false;
      
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      
      if (decoded is Map && decoded.containsKey('albums')) {
        final List<dynamic> albumsJson = decoded['albums'];
        final albums = albumsJson.map((json) => Album.fromJson(json)).toList();
        
        // Salva la configurazione importata
        await addConfig(configName);
        await saveAlbums(albums, configName);
        
        print('✅ Configurazione "$configName" importata da: $importPath');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Errore importazione configurazione: $e');
      return false;
    }
  }

  // ========== METODO PER COMPATIBILITÀ (usato da altri file) ==========
  // Rinomina il metodo originale per evitare conflitto
  Future<void> updateAlbumLegacy(Album updatedAlbum) async {
    await updateAlbum(updatedAlbum, null);
  }
}