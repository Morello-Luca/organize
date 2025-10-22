class Carousel {
  final String id;
  String title;
  List<String> imagePaths;
  String aspectRatio;
  final String? sourceFolder;

  Carousel({
    required this.id,
    required this.title,
    required this.imagePaths,
    this.aspectRatio = '19:13',
    this.sourceFolder, 
  });

  Carousel copyWith({String? title, List<String>? imagePaths,String? aspectRatio,String? sourceFolder,}) {
    return Carousel(
      id: id,
      title: title ?? this.title,
      imagePaths: imagePaths ?? this.imagePaths,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      sourceFolder: sourceFolder ?? this.sourceFolder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'imagePaths': imagePaths,
        'aspectRatio': aspectRatio,
        'sourceFolder': sourceFolder,
      };

  factory Carousel.fromJson(Map<String, dynamic> json) => Carousel(
        id: json['id'],
        title: json['title'],
        imagePaths: List<String>.from(json['imagePaths'] ?? []),
        aspectRatio: json['aspectRatio'] ?? '19:13',
        sourceFolder: json['sourceFolder'],
      );
}