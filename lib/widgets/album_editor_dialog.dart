import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/album.dart';

class AlbumEditorDialog extends StatefulWidget {
  final Album album;

  const AlbumEditorDialog({super.key, required this.album});

  @override
  State<AlbumEditorDialog> createState() => _AlbumEditorDialogState();
}

class _AlbumEditorDialogState extends State<AlbumEditorDialog> {
  late TextEditingController _nameController;
  String? _coverImagePath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.album.name);
    _coverImagePath = widget.album.coverImagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _coverImagePath = result.files.single.path;
      });
    }
  }

  void _save() {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un nome per l\'album')),
      );
      return;
    }

    // ✅ CORRETTO: usa copyWith che mantiene TUTTI i dati
    final editedAlbum = widget.album.copyWith(
      name: newName,
      coverImagePath: _coverImagePath,
      lastEdited: DateTime.now(), // Aggiorna timestamp
    );

    print('💾 Album modificato: ${editedAlbum.name}');
    print('   - Caroselli: ${editedAlbum.carousels.length}');
    print('   - Source Folder: ${editedAlbum.sourceFolder}');
    print('   - Immagini totali: ${editedAlbum.imagePaths.length}');

    Navigator.of(context).pop(editedAlbum);
  }

  void _removeCoverImage() {
    setState(() {
      _coverImagePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifica Album'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome Album',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            
            // Sezione Copertina
            Text(
              'Copertina Album',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _coverImagePath != null && File(_coverImagePath!).existsSync()
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_coverImagePath!),
                              width: 200,
                              height: 150,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholderCover();
                              },
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                onPressed: _removeCoverImage,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _buildPlaceholderCover(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _coverImagePath != null ? 'Clicca per cambiare' : 'Clicca per aggiungere copertina',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),

            
           
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _save, 
          child: const Text('Salva')
        ),
      ],
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            'Aggiungi copertina',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}