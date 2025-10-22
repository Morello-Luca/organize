import 'package:flutter/material.dart';
import '../models/album_filters.dart'; // Aggiungi questo import

class ViewToggleButtons extends StatelessWidget {
  final String currentView;
  final GridSize gridSize;
  final ValueChanged<String> onViewChanged;
  final ValueChanged<GridSize> onGridSizeChanged;

  const ViewToggleButtons({
    super.key,
    required this.currentView,
    required this.gridSize,
    required this.onViewChanged,
    required this.onGridSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle Vista
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'grid',
              icon: Icon(Icons.grid_view),
              label: Text('Griglia'),
            ),
            ButtonSegment(
              value: 'list',
              icon: Icon(Icons.view_list),
              label: Text('Lista'),
            ),
          ],
          selected: {currentView},
          onSelectionChanged: (Set<String> newSelection) {
            onViewChanged(newSelection.first);
          },
        ),
        
        const SizedBox(width: 8),
        
        // Toggle Dimensioni Griglia (solo se vista griglia)
        if (currentView == 'grid') 
          SegmentedButton<GridSize>(
            segments: const [
              ButtonSegment(
                value: GridSize.small,
                icon: Icon(Icons.view_comfy),
                label: Text('S'),
              ),
              ButtonSegment(
                value: GridSize.medium,
                icon: Icon(Icons.grid_on),
                label: Text('M'),
              ),
              ButtonSegment(
                value: GridSize.large,
                icon: Icon(Icons.crop_square),
                label: Text('L'),
              ),
            ],
            selected: {gridSize},
            onSelectionChanged: (Set<GridSize> newSelection) {
              onGridSizeChanged(newSelection.first);
            },
          ),
      ],
    );
  }
}