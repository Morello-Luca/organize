import 'package:flutter/material.dart';

class AlbumSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onFilterPressed;
  final bool hasActiveFilters;

  const AlbumSearchBar({
    super.key,
    required this.onSearchChanged,
    required this.onFilterPressed,
    required this.hasActiveFilters,
  });

  @override
  State<AlbumSearchBar> createState() => _AlbumSearchBarState();
}

class _AlbumSearchBarState extends State<AlbumSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          widget.onSearchChanged('');
                        },
                      )
                    : null,
                hintText: 'Cerca album...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: widget.hasActiveFilters,
            child: IconButton(
              icon: const Icon(Icons.filter_list_rounded),
              onPressed: widget.onFilterPressed,
            ),
          ),
        ],
      ),
    );
  }
}