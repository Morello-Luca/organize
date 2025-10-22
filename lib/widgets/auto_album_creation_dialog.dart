// widgets/auto_album_creation_dialog.dart
import 'package:flutter/material.dart';
import '../services/folder_sync_service.dart';
import '../models/album.dart';

class AutoAlbumCreationDialog extends StatefulWidget {
  final FolderSyncService syncService;
  final List<Album> existingAlbums;

  const AutoAlbumCreationDialog({
    super.key,
    required this.syncService,
    required this.existingAlbums,
  });

  @override
  State<AutoAlbumCreationDialog> createState() => _AutoAlbumCreationDialogState();
}

class _AutoAlbumCreationDialogState extends State<AutoAlbumCreationDialog> {
  List<Album> _detectedAlbums = [];
  Set<String> _selectedAlbums = {};
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _scanFolders();
  }

  Future<void> _scanFolders() async {
    setState(() => _isScanning = true);
    
    final albums = await widget.syncService.createAlbumsFromFolders();
    
    // Filtra album che non esistono già
    final existingNames = widget.existingAlbums.map((a) => a.name).toSet();
    _detectedAlbums = albums.where((a) => !existingNames.contains(a.name)).toList();
    
    // Seleziona tutti automaticamente
    _selectedAlbums = Set.from(_detectedAlbums.map((a) => a.id));
    
    setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crea Album da Cartelle'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isScanning
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scansione cartelle in corso...'),
                ],
              )
            : _detectedAlbums.isEmpty
                ? const Text('Nessuna nuova cartella trovata.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trovati ${_detectedAlbums.length} album:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _detectedAlbums.length,
                          itemBuilder: (context, index) {
                            final album = _detectedAlbums[index];
                            return CheckboxListTile(
                              title: Text(album.name),
                              subtitle: Text('${album.imagePaths.length} immagini'),
                              value: _selectedAlbums.contains(album.id),
                              onChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedAlbums.add(album.id);
                                  } else {
                                    _selectedAlbums.remove(album.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _selectedAlbums.isEmpty
              ? null
              : () {
                  final selected = _detectedAlbums
                      .where((a) => _selectedAlbums.contains(a.id))
                      .toList();
                  Navigator.pop(context, selected);
                },
          child: const Text('Crea Album'),
        ),
      ],
    );
  }
}