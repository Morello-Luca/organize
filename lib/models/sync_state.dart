// models/sync_state.dart
class SyncState {
  final DateTime lastSync;
  final int totalImages;
  final int assignedImages;
  final int unassignedImages;
  final List<String> folderAlbums;

  SyncState({
    required this.lastSync,
    required this.totalImages,
    required this.assignedImages,
    required this.unassignedImages,
    required this.folderAlbums,
  });

  SyncState copyWith({
    DateTime? lastSync,
    int? totalImages,
    int? assignedImages,
    int? unassignedImages,
    List<String>? folderAlbums,
  }) {
    return SyncState(
      lastSync: lastSync ?? this.lastSync,
      totalImages: totalImages ?? this.totalImages,
      assignedImages: assignedImages ?? this.assignedImages,
      unassignedImages: unassignedImages ?? this.unassignedImages,
      folderAlbums: folderAlbums ?? this.folderAlbums,
    );
  }
}