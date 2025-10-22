import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/album.dart';
import '../models/album_filters.dart';
import '../services/storage_service.dart';
import '../services/folder_sync_service.dart'; // <-- AGGIUNGI QUESTO
import '../widgets/navigation_rail.dart';
import '../widgets/album_editor_dialog.dart';
import '../widgets/search_album_bar.dart';
import '../widgets/album_filter_sheet.dart';
import '../widgets/view_toggle_buttons.dart';
import 'source_album_view.dart';
import 'custom_album_view.dart';
import 'package:path/path.dart' as path;
import '../widgets/auto_album_creation_dialog.dart';
// SPOSTA _GridConfig ALL'INIZIO DEL FILE
class _GridConfig {
  final double baseWidth;
  final double aspectRatio;
  final double spacing;

  const _GridConfig({
    required this.baseWidth,
    required this.aspectRatio,
    required this.spacing,
  });
}

class SetListPage extends StatefulWidget {
  const SetListPage({super.key});

  @override
  State<SetListPage> createState() => _SetListPageState();
}

class _SetListPageState extends State<SetListPage> {
  final StorageService _storage = StorageService();
  String? _sourceFolderPath;
  List<Album> _albums = [];
  FolderSyncService? _syncService;
  
  AlbumFilters _filters = const AlbumFilters();

  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _loadData();
  }

  @override
  void dispose() {
    _isMounted = false;
    super.dispose();
  }

  // METODO HELPER SICURO PER setState
  void _safeSetState(VoidCallback fn) {
    if (_isMounted) {
      setState(fn);
    }
  }

  // In setlist_page.dart - SOSTITUISCI _loadData()
  Future<void> _loadData() async {
    final source = await _storage.getSourceFolderPath();
    
    // CARICAMENTO INTELLIGENTE: prima cerca nel JSON, poi fallback
    List<Album> albums = await _storage.loadAlbumsWithFallback();
    
    _safeSetState(() {
      _sourceFolderPath = source;
      _albums = albums;
      
      if (_sourceFolderPath != null) {
        _syncService = FolderSyncService(sourceFolderPath: _sourceFolderPath!);
      }
    });
    
    if (_syncService != null && _isMounted) {
      await _performSync();
    }
  }

  Future<void> _performSync() async {
    if (_syncService == null || !_isMounted) return;
    
    final result = await _syncService!.syncAlbums(_albums);
    
    if (result.updatedAlbums.isNotEmpty && _isMounted) {
      // Aggiorna album con percorsi corretti
      for (final updatedAlbum in result.updatedAlbums) {
        await _storage.updateAlbum(updatedAlbum);
      }
      
      // Ricarica dati
      final updatedAlbums = await _storage.getAlbums();
      _safeSetState(() {
        _albums = updatedAlbums;
      });
      
      _showSnackBar('Sync completato: ${result.updatedAlbums.length} album aggiornati');
    }
  }

  // Nuovo metodo per creazione album automatica
  Future<void> _createAlbumsFromFolders() async {
    if (_syncService == null) {
      _showSnackBar('Configura prima la cartella sorgente');
      return;
    }

    final newAlbums = await showDialog<List<Album>>(
      context: context,
      builder: (context) => AutoAlbumCreationDialog(
        syncService: _syncService!,
        existingAlbums: _albums,
      ),
    );

    if (newAlbums != null && newAlbums.isNotEmpty && _isMounted) {
      _safeSetState(() {
        _albums.addAll(newAlbums);
      });
      await _storage.saveAlbums(_albums);
      _showSnackBar('Creati ${newAlbums.length} album dalle cartelle');
    }
  }

  void _showSnackBar(String message) {
    if (_isMounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // setlist_page.dart - MODIFICA _addAlbum
  Future<void> _addAlbum() async {
    final newAlbum = Album(
      id: const Uuid().v4(), 
      name: 'Nuovo Album', 
      imagePaths: [],
      carousels: [],
      createdAt: DateTime.now(),
      lastEdited: DateTime.now(),
    );
    
    // Crea cartella per il nuovo album
    if (_syncService != null) {
      final albumFolderPath = await _syncService!.createFolderForAlbum(newAlbum.name);
      newAlbum.sourceFolder = path.relative(albumFolderPath, from: _syncService!.sourceFolderPath);
    }
    
    _safeSetState(() {
      _albums.add(newAlbum);
    });
    await _storage.saveAlbums(_albums);
    _editAlbum(newAlbum);
  }

  Future<void> _editAlbum(Album album) async {
    final edited = await showDialog<Album>(
      context: context,
      builder: (context) => AlbumEditorDialog(album: album),
    );

    if (edited != null && _isMounted) {
      final updatedAlbum = edited.copyWith(lastEdited: DateTime.now());
      
      _safeSetState(() {
        final index = _albums.indexWhere((a) => a.id == updatedAlbum.id);
        if (index != -1) {
          _albums[index] = updatedAlbum; 
        }
      });
      await _storage.updateAlbum(updatedAlbum);
    }
  }

  Future<void> _deleteAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Conferma cancellazione'),
            content: Text('Vuoi cancellare l\'album "${album.name}"?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancella')),
            ],
          ),
        ) ??
        false;

    if (confirmed && _isMounted) {
      _safeSetState(() {
        _albums.removeWhere((a) => a.id == album.id);
      });
      await _storage.saveAlbums(_albums);
    }
  }

  void _openAlbum(Album album) async {
    print('🎯 APRO ALBUM: ${album.name} - lastEdited: ${album.lastEdited}');
    
    final updatedAlbum = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumViewPage(album: album),
      ),
    );

    // CONTROLLO CRITICO: verifica se il widget è ancora montato
    if (!_isMounted) return;

    if (updatedAlbum != null && updatedAlbum is Album) {
      print('🔄 ALBUM RITORNA: ${updatedAlbum.name} - lastEdited: ${updatedAlbum.lastEdited}');
      
      final albumWithTimestamp = updatedAlbum.copyWith(lastEdited: DateTime.now());
      
      _safeSetState(() {
        final index = _albums.indexWhere((a) => a.id == albumWithTimestamp.id);
        if (index != -1) {
          _albums[index] = albumWithTimestamp;
          print('✅ ALBUM AGGIORNATO NELLA LISTA');
        } else {
          print('❌ ALBUM NON TROVATO NELLA LISTA');
        }
      });
      
      await _storage.updateAlbum(albumWithTimestamp);
      print('💾 ALBUM SALVATO NEL STORAGE');
      
      // FORZA IL REBUILD DELLA LISTA ORDINATA
      if (_isMounted) {
        final sortedAlbums = _applySorting(_albums);
        print('📊 ALBUM ORDINATI: ${sortedAlbums.map((a) => '${a.name} (${a.lastEdited})').toList()}');
      }
    }
  }

  void _openSourceAlbum() {
    if (_sourceFolderPath == null || !_isMounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SourceAlbumViewPage(folderPath: _sourceFolderPath!),
      ),
    );
  }

  // === NUOVI METODI PER FILTRI E RICERCA ===

  List<Album> get _filteredAlbums {
    List<Album> filtered = List.from(_albums);
    
    if (_filters.searchQuery.isNotEmpty) {
      filtered = filtered.where((album) => 
        album.name.toLowerCase().contains(_filters.searchQuery.toLowerCase())
      ).toList();
    }
    
    filtered = _applySorting(filtered);
    
    return filtered;
  }
  
  // In _applySorting(), aggiungi il caso 'last_edit':
  List<Album> _applySorting(List<Album> albums) {
    switch (_filters.sortBy) {
      case 'name':
        albums.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'date':
        albums.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'last_edit':
        albums.sort((a, b) => a.lastEdited.compareTo(b.lastEdited));
        break;
      case 'images':
        albums.sort((a, b) => a.imagePaths.length.compareTo(b.imagePaths.length));
        break;
    }
    
    if (_filters.sortOrder == 'desc') {
      albums = albums.reversed.toList();
    }
    
    return albums;
  }

  
  void _openFilterSheet() {
    if (!_isMounted) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AlbumFilterSheet(
        initialFilters: _filters,
        onFiltersApplied: (newFilters) {
          if (_isMounted) {
            _safeSetState(() {
              _filters = newFilters;
            });
          }
        },
      ),
    );
  }

  // === UI OTTIMIZZATA ===

  Widget _buildCompactHeader() {
    return Column(
      children: [
        // Riga 1: Titolo + Azioni COMPATTI
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Titolo più compatto
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Album',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_filteredAlbums.length} ${_filteredAlbums.length == 1 ? 'raccolta' : 'raccolte'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            
            // Bottone più compatto
            Row(
              children: [
                // Bottone Sync
                if (_syncService != null)
                  IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: _performSync,
                    tooltip: 'Sincronizza con cartelle',
                  ),
                
                // Bottone Auto-create
                if (_syncService != null)
                  IconButton(
                    icon: const Icon(Icons.create_new_folder),
                    onPressed: _createAlbumsFromFolders,
                    tooltip: 'Crea album da cartelle',
                  ),
                
                // Bottone Nuovo esistente
                FilledButton(
                  onPressed: _addAlbum,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18),
                      SizedBox(width: 4),
                      Text('Nuovo'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // Riga 2: Search + Filtri
        AlbumSearchBar(
          onSearchChanged: (query) {
            if (_isMounted) {
              _safeSetState(() {
                _filters = _filters.copyWith(searchQuery: query);
              });
            }
          },
          onFilterPressed: _openFilterSheet,
          hasActiveFilters: _filters.hasActiveFilters,
        ),
        
        const SizedBox(height: 8),
        
        // Riga 3: Status + Toggle Vista COMPATTI
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSyncStatusCompact(),
            
            ViewToggleButtons(
              currentView: _filters.viewType,
              gridSize: _filters.gridSize,
              onViewChanged: (view) {
                if (_isMounted) {
                  _safeSetState(() {
                    _filters = _filters.copyWith(viewType: view);
                  });
                }
              },
              onGridSizeChanged: (size) {
                if (_isMounted) {
                  _safeSetState(() {
                    _filters = _filters.copyWith(gridSize: size);
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildSyncStatusCompact() {
    return FutureBuilder<bool>(
      future: _storage.isSourceFolderSynchronized(),
      builder: (context, snapshot) {
        final isSynced = snapshot.data ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSynced 
              ? Colors.green.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSynced ? Colors.green : Colors.orange,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSynced ? Icons.cloud_done : Icons.cloud_off,
                size: 14,
                color: isSynced ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                isSynced ? 'Sincronizzato' : 'Configura',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSynced ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_album_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          Text(
            _filters.hasActiveFilters ? 'Nessun risultato' : 'Nessun album creato',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _filters.hasActiveFilters 
              ? 'Prova a modificare i filtri di ricerca'
              : 'Crea il tuo primo album per iniziare',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (!_filters.hasActiveFilters)
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Crea Primo Album'),
              onPressed: _addAlbum,
            )
          else
            OutlinedButton(
              onPressed: () {
                if (_isMounted) {
                  _safeSetState(() {
                    _filters = const AlbumFilters();
                  });
                }
              },
              child: const Text('Reset Filtri'),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    final albums = _filteredAlbums;
    
    if (albums.isEmpty) {
      return _buildEmptyState();
    }

    switch (_filters.viewType) {
      case 'list':
        return _buildListView(albums);
      case 'grid':
      default:
        return _buildGridView(albums);
    }
  }

  Widget _buildGridView(List<Album> albums) {
    final config = _getGridConfig(_filters.gridSize);
    
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final crossAxisCount = (maxWidth / config.baseWidth).floor().clamp(1, 8);
      
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: config.spacing,
          mainAxisSpacing: config.spacing,
          childAspectRatio: config.aspectRatio,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return _AlbumCard(
            album: album,
            onOpen: () => _openAlbum(album),
            onEdit: () => _editAlbum(album),
            onDelete: () => _deleteAlbum(album),
            cardSize: _filters.gridSize,
          );
        },
      );
    });
  }

  _GridConfig _getGridConfig(GridSize size) {
    switch (size) {
      case GridSize.small:
        return _GridConfig(
          baseWidth: 140,
          aspectRatio: 0.7,
          spacing: 8,
        );
      case GridSize.medium:
        return _GridConfig(
          baseWidth: 180,
          aspectRatio: 0.75,
          spacing: 12,
        );
      case GridSize.large:
        return _GridConfig(
          baseWidth: 240,
          aspectRatio: 0.8,
          spacing: 16,
        );
    }
  }

  Widget _buildListView(List<Album> albums) {
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return ListTile(
          leading: _buildListTileImage(album),
          title: Text(album.name),
          subtitle: Text('${album.imagePaths.length} immagini'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editAlbum(album);
              if (value == 'delete') _deleteAlbum(album);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Modifica')),
              const PopupMenuItem(value: 'delete', child: Text('Cancella')),
            ],
          ),
          onTap: () => _openAlbum(album),
        );
      },
    );
  }

  Widget _buildListTileImage(Album album) {
    if (album.coverImagePath != null && File(album.coverImagePath!).existsSync()) {
      return Image.file(
        File(album.coverImagePath!),
        width: 50,
        height: 50,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: 50,
      height: 50,
      color: Colors.grey[200],
      child: Icon(Icons.photo_album_outlined, color: Colors.grey[400]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const AppNavigationRail(selectedIndex: 1),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildCompactHeader(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _buildCurrentView(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// RIMUOVI la definizione duplicata di _GridConfig da qui
// (è già stata spostata all'inizio del file)

class _AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final GridSize cardSize;

  const _AlbumCard({
    required this.album,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.cardSize,
  });

  Widget _buildCover(BuildContext context) {
    if (album.coverImagePath != null && File(album.coverImagePath!).existsSync()) {
      return Image.file(
        File(album.coverImagePath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderCover();
        },
      );
    }
    return _buildPlaceholderCover();
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.photo_album_outlined,
          size: _getIconSizeForCardSize(cardSize),
          color: Colors.grey[400],
        ),
      ),
    );
  }

  double _getIconSizeForCardSize(GridSize size) {
    switch (size) {
      case GridSize.small:
        return 32;
      case GridSize.medium:
        return 48;
      case GridSize.large:
        return 64;
    }
  }

  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.more_vert, color: Colors.white, size: _getMenuIconSizeForCardSize(cardSize)),
      ),
      splashRadius: 20,
      position: PopupMenuPosition.under,
      onSelected: (String result) {
        if (result == 'edit') {
          onEdit();
        } else if (result == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Modifica'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Text(
                'Cancella',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _getMenuIconSizeForCardSize(GridSize size) {
    switch (size) {
      case GridSize.small:
        return 16;
      case GridSize.medium:
        return 18;
      case GridSize.large:
        return 20;
    }
  }

  EdgeInsets _getPaddingForCardSize(GridSize size) {
    switch (size) {
      case GridSize.small:
        return const EdgeInsets.all(8);
      case GridSize.medium:
        return const EdgeInsets.all(12);
      case GridSize.large:
        return const EdgeInsets.all(16);
    }
  }

  TextStyle _getTitleStyleForCardSize(GridSize size, BuildContext context) {
    switch (size) {
      case GridSize.small:
        return Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ) ?? const TextStyle();
      case GridSize.medium:
        return Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ) ?? const TextStyle();
      case GridSize.large:
        return Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ) ?? const TextStyle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildCover(context),
                  ),
                  
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildPopupMenu(context),
                  ),

                  if (album.imagePaths.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${album.imagePaths.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            Container(
              padding: _getPaddingForCardSize(cardSize),
              child: Text(
                album.name,
                style: _getTitleStyleForCardSize(cardSize, context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}