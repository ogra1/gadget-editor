import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft, // Changed from centerLeft to topLeft
      child: Container(
        alignment: Alignment.topLeft, // Changed from centerLeft to topLeft
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.start, // Changed from center to start
          crossAxisAlignment: CrossAxisAlignment.start, // Keep left align
          children: [
            Icon(Icons.download_for_offline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Search for gadget snaps from the Snap Store\nor load local gadget snaps',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
