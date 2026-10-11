import 'package:flutter/material.dart';

/// A compact chip showing which architecture the loaded gadget snap
/// targets, pinned to the top-right of the page header so the user always
/// sees what they are editing.
///
/// The architecture list comes from `meta/snap.yaml` of the unpacked snap
/// and is the same for store-downloaded and local snaps. `all` is rendered
/// as-is (the snap targets every architecture).
class ArchBadge extends StatelessWidget {
  const ArchBadge({super.key, required this.architectures});

  final List<String> architectures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = architectures.join(' / ');
    return Tooltip(
      message: 'Snap architecture: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
