import '../models/carousel.dart';

class Album {
  final String id;
  final String name;
  final List<String> imagePaths;
  final String? coverImagePath;
  final List<Carousel> carousels;
  final DateTime createdAt;
  final DateTime lastEdited;
  String? sourceFolder;

  Album({
    required this.id,
    required this.name,
    required this.imagePaths,
    this.coverImagePath,
    this.carousels = const [],
    DateTime? createdAt,
    DateTime? lastEdited,
    this.sourceFolder,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastEdited = lastEdited ?? DateTime.now();

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'],
      name: json['name'],
      imagePaths: List<String>.from(json['imagePaths'] ?? []),
      coverImagePath: json['coverImagePath'],
      carousels: (json['carousels'] as List<dynamic>?)
          ?.map((e) => Carousel.fromJson(e))
          .toList() ?? [],
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      lastEdited: json['lastEdited'] != null 
          ? DateTime.parse(json['lastEdited']) 
          : DateTime.now(),
      sourceFolder: json['sourceFolder'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imagePaths': imagePaths,
      'coverImagePath': coverImagePath,
      'carousels': carousels.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'lastEdited': lastEdited.toIso8601String(),
      'sourceFolder': sourceFolder,
    };
  }

  Album copyWith({
    String? name,
    List<String>? imagePaths,
    String? coverImagePath,
    List<Carousel>? carousels,
    DateTime? lastEdited,
    String? sourceFolder,
  }) {
    return Album(
      id: id,
      name: name ?? this.name,
      imagePaths: imagePaths ?? this.imagePaths,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      carousels: carousels ?? this.carousels,
      createdAt: createdAt,
      lastEdited: lastEdited ?? this.lastEdited,
      sourceFolder: sourceFolder ?? this.sourceFolder,
    );
  }
}