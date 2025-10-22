class AlbumFilters {
  final String searchQuery;
  final String sortBy; // 'name', 'date', 'size', 'images'
  final String sortOrder; // 'asc', 'desc'
  final String viewType; // 'grid', 'list'
  final GridSize gridSize;

  const AlbumFilters({
    this.searchQuery = '',
    this.sortBy = 'name',
    this.sortOrder = 'desc',
    this.viewType = 'grid',
    this.gridSize = GridSize.medium,
  });

  AlbumFilters copyWith({
    String? searchQuery,
    String? sortBy,
    String? sortOrder,
    String? viewType,
    GridSize? gridSize,
  }) {
    return AlbumFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      viewType: viewType ?? this.viewType,
      gridSize: gridSize ?? this.gridSize,
    );
  }

  bool get hasActiveFilters {
    return searchQuery.isNotEmpty || 
           sortBy != 'name' || 
           sortOrder != 'asc' ||
           gridSize != GridSize.medium;
  }
}

enum GridSize { small, medium, large }