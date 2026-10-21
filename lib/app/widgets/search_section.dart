import 'package:flutter/material.dart';

class SearchSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Function(String) onSubmitted;

  const SearchSection({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
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
