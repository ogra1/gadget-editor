import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'editable_text_field.dart';

/// Inline editor for the store API key.
///
/// The key is the `MODEL_APIKEY` environment variable of the
/// `prepare-device` hook; it is consumed on first boot of an Ubuntu Core
/// system when the device is onboarded to a store. Being a single scalar it
/// is edited in place with one [EditableTextField] rather than through the
/// add-dialog flow the collection sections use.
///
/// This widget is stateless and read-only with respect to the document: it
/// renders [currentKey] and reports the user's chosen value through
/// [onSave]. Persistence (loading, editing, writing the backing snap.yaml
/// and refreshing the display) is owned by the parent, which routes the edit
/// through the [GadgetYaml] service.
class ApiKeySection extends StatelessWidget {
  /// The current value of `MODEL_APIKEY` (`''` when unset or empty).
  final String currentKey;

  /// Called with the value the user committed (Enter / check button).
  final ValueChanged<String> onSave;

  const ApiKeySection({
    super.key,
    required this.currentKey,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: tinted icon chip + title, matching the other sections.
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    YaruIcons.key,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Store API Key',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Used by the prepare-device hook to onboard the device to a '
              'dedicated store.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            EditableTextField(
              key: const ValueKey('api-key-field'),
              label: 'MODEL_APIKEY',
              text: currentKey,
              onSave: onSave,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
