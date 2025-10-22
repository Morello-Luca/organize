import 'dart:io';

import 'package:flutter/material.dart';

class SourceAlbumViewPage extends StatelessWidget {
  final String folderPath;

  const SourceAlbumViewPage({super.key, required this.folderPath});

  @override
  Widget build(BuildContext context) {
    final dir = Directory(folderPath);
    final files = dir.existsSync()
        ? dir
            .listSync()
            .whereType<File>()
            .where((file) =>
                ['.png', '.jpg', '.jpeg', '.gif']
                    .any((ext) => file.path.toLowerCase().endsWith(ext)))
            .toList()
        : [];

    return Scaffold(
      appBar: AppBar(title: const Text('Album Sorgente')),
      body: files.isEmpty
          ? const Center(child: Text('Nessuna immagine trovata'))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image),
                );
              },
            ),
    );
  }
}
