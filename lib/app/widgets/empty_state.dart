import 'package:flutter/material.dart';

/// The placeholder shown in the main pane while no gadget snap is loaded.
///
/// A centered, lightly bordered card with descriptive text pointing at the
/// sidebar's two entry points (the store search box and the local loader).
///
/// It is intentionally self-contained: the card is centered and wrapped in a
/// [FittedBox] with [BoxFit.scaleDown], so it is perfectly centered when the
/// pane is roomy and gently shrinks to fit when the pane is smaller than the
/// card's natural size (e.g. the window's computed default size). It can
/// therefore never overflow, regardless of window dimensions.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset('assets/icon.png', width: 56, height: 56),
                ),
                const SizedBox(height: 16),
                Text(
                  'No gadget snap loaded',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use the search box in the sidebar to find a gadget snap '
                  'in the Snap Store, or load a .snap file from disk with '
                  'the "Load Local Snap" button.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tip: the search box is already focused \u2014 just type a '
                  'snap name and press Enter.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
