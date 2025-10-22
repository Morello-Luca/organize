import 'package:flutter/material.dart';
import '../models/album_filters.dart';

import 'package:flutter/material.dart';
import '../models/album_filters.dart';

class AlbumFilterSheet extends StatefulWidget {
  final AlbumFilters initialFilters;
  final Function(AlbumFilters) onFiltersApplied;

  const AlbumFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onFiltersApplied,
  });

  @override
  State<AlbumFilterSheet> createState() => _AlbumFilterSheetState();
}

class _AlbumFilterSheetState extends State<AlbumFilterSheet> {
  late AlbumFilters _currentFilters;

  @override
  void initState() {
    super.initState();
    _currentFilters = widget.initialFilters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filtri e Ordinamento',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_currentFilters.hasActiveFilters)
                TextButton(
                  onPressed: _resetFilters,
                  child: const Text('Reset'),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Ordinamento
          _buildSortSection(),
          const SizedBox(height: 24),

          // Azioni
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ordina per',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'name',
              icon: Icon(Icons.sort_by_alpha),
              label: Text('Nome'),
            ),
            ButtonSegment(
              value: 'date',
              icon: Icon(Icons.date_range),
              label: Text('Data Creazione'),
            ),
            ButtonSegment(
              value: 'last_edit',
              icon: Icon(Icons.edit_calendar),
              label: Text('Ultima Modifica'),
            ),
            ButtonSegment(
              value: 'images',
              icon: Icon(Icons.photo_library),
              label: Text('Immagini'),
            ),
          ],
          selected: {_currentFilters.sortBy},
          onSelectionChanged: (Set<String> newSelection) {
            setState(() {
              _currentFilters = _currentFilters.copyWith(sortBy: newSelection.first);
            });
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'asc',
              icon: Icon(Icons.arrow_downward),
              label: Text('Derescente'),
            ),
            ButtonSegment(
              value: 'desc',
              icon: Icon(Icons.arrow_upward),
              label: Text('Crescente'),
            ),
          ],
          selected: {_currentFilters.sortOrder},
          onSelectionChanged: (Set<String> newSelection) {
            setState(() {
              _currentFilters = _currentFilters.copyWith(sortOrder: newSelection.first);
            });
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () {
              widget.onFiltersApplied(_currentFilters);
              Navigator.pop(context);
            },
            child: const Text('Applica'),
          ),
        ),
      ],
    );
  }

  void _resetFilters() {
    setState(() {
      _currentFilters = const AlbumFilters();
    });
  }
}