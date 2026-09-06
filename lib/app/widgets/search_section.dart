import 'package:flutter/material.dart';

class SearchSection extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSubmitted;

  const SearchSection({
    super.key,
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Search Snap Store...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        suffixIcon: const Icon(Icons.search),
      ),
      onSubmitted: onSubmitted,
    );
  }
}
