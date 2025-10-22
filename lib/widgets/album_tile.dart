import 'package:flutter/material.dart';
import '../models/album.dart';
import 'dart:io';


class AlbumTile extends StatelessWidget {
  final Album album;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  const AlbumTile({
    super.key,
    required this.album,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: album.coverImagePath != null
          ? Image.file(
              File(album.coverImagePath!),
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
            )
          : const Icon(Icons.photo_album_outlined, size: 50),
      title: Text(album.name),
      trailing: Wrap(
        spacing: 8,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Modifica Album',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Cancella Album',
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}
