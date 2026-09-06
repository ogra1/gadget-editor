import 'package:flutter/material.dart';

class LocalSnapLoader extends StatelessWidget {
  final VoidCallback onPressed;

  const LocalSnapLoader({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface, // Use surface color for better contrast
        foregroundColor: Theme.of(context).colorScheme.onSurface, // Use appropriate text color
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(context).dividerColor, // Add border like search field
            width: 1,
          ),
        ),
        elevation: 0, // Remove elevation for cleaner look
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 16),
          SizedBox(width: 8),
          Text('Load Local Snap'),
        ],
      ),
    );
  }
}
