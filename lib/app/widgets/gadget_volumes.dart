import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/services/gadget_yaml_service.dart';

import 'editable_text_field.dart';
import 'partition_size_editor.dart';

class GadgetVolumesSection extends StatefulWidget {
  final dynamic volumes;
  final VoidCallback? onEdit;
  final bool showEditButton;
  final String? filePath;
  final VoidCallback? refreshCallback;
  final Function(String)? onStatusUpdate;

  const GadgetVolumesSection({
    super.key,
    required this.volumes,
    this.onEdit,
    this.showEditButton = true,
    this.filePath,
    this.refreshCallback,
    this.onStatusUpdate,
  });

  @override
  State<GadgetVolumesSection> createState() => _GadgetVolumesSectionState();
}

class _GadgetVolumesSectionState extends State<GadgetVolumesSection> {
  /// Per-volume handle to each volume-name [EditableTextField], so a
  /// rejected save (e.g. an empty name) can snap the field back to the
  /// original value. Keyed by volume name; a [ValueKey] on the field keeps
  /// the right handle attached even if the volume order changes.
  final Map<String, EditableTextFieldState> _volumeNameFields = {};

  @override
  Widget build(BuildContext context) {
    if (widget.volumes == null || (widget.volumes is YamlMap && widget.volumes.isEmpty)) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(16),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Volumes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text('No volumes defined.'),
          ],
        ),
      );
    }

    if (widget.volumes is YamlMap) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Volumes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.volumes.entries.map((entry) {
                final volumeName = entry.key;
                final volumeData = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage, size: 20, color: Color(0xFF8E8E8E)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: EditableTextField(
                            key: ValueKey(volumeName),
                            text: volumeName,
                            label: 'Image Name',
                            onSave: (newName) {
                              // An empty (or whitespace-only) name has nowhere
                              // to be written and would leave a blank chip.
                              // Reject it: show an error and snap the field back
                              // to the original value without touching the file.
                              if (newName.trim().isEmpty) {
                                widget.onStatusUpdate
                                    ?.call('Error: Volume name cannot be empty');
                                _volumeNameFields[volumeName]?.resetToOriginal();
                                return;
                              }
                              // Update the volume name in the YAML file
                              if (widget.filePath != null) {
                                _updateVolumeNameInFile(widget.filePath!, volumeName, newName);
                              }
                            },
                            style: const TextStyle(fontSize: 16),
                            onStateCreated: (state) {
                              _volumeNameFields[volumeName] = state;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Caption mirroring the "Image Name" caption above.
                    Text(
                      'Partitions',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (volumeData['structure'] != null && volumeData['structure'] is List)
                      _buildPartitionVisualization(context, volumeData['structure'], volumeName)
                    else if (volumeData['structure'] == null)
                      const Text('No structure field found')
                    else
                      const Text('Structure is not a list'),
                    const SizedBox(height: 16),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Volumes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text('No volumes defined. Click the edit icon to add volumes.'),
        ],
      ),
    );
  }

  // Function to update volume name in the YAML file
  void _updateVolumeNameInFile(String filePath, String oldName, String newName) {
    if (newName.isEmpty || newName == oldName) return;
    final status = widget.onStatusUpdate;
    final refresh = widget.refreshCallback;
    try {
      // renameVolume inserts the new key before removing the old one, so the
      // volumes map is never empty mid-operation and sibling volumes (plus
      // comments/formatting) survive the edit.
      final yaml = GadgetYaml.fromFile(filePath);
      yaml.renameVolume(oldName, newName);
      yaml.save();
      status?.call('Volume name updated successfully');
      refresh?.call();
    } on GadgetYamlException catch (e) {
      status?.call('Error updating volume name: ${e.message}');
    } catch (e) {
      status?.call('Error updating volume name: $e');
    }
  }

  Widget _buildPartitionVisualization(BuildContext context, List structure, String volumeName) {
    if (structure.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text('No partitions to display'),
        ),
      );
    }
    // Parse all sizes to calculate total size
    double totalSize = 0;
    List<Map<String, dynamic>> parsedStructures = [];

    for (var item in structure) {
      final sizeStr = item['size'];
      if (sizeStr != null) {
        double sizeValue = _parseSize(sizeStr);
        parsedStructures.add({
          'name': item['name'] ?? 'Unnamed',
          'size': sizeValue,
          'role': item['role'],
          'type': item['type'],
          'raw': item,
        });
        totalSize += sizeValue;
      }
    }

    if (totalSize <= 0) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text('No valid partition sizes'),
        ),
      );
    }
    // Create proportional visualization. Each partition is rendered by
    // [_buildPartitionTile] so the "whole tile is tappable" behavior lives in
    // one place.
    return SizedBox(
      height: 80,
      child: Row(
        children: [
          for (var item in parsedStructures)
            Expanded(
              flex: (item['size']! / totalSize * 1000).toInt() > 0 ? (item['size']! / totalSize * 1000).toInt() : 1,
              child: _buildPartitionTile(context, item, volumeName),
            ),
        ],
      ),
    );
  }

  /// True when [role] names a partition the app allows resizing
  /// (system-seed and system-data). The pencil marker is shown for exactly
  /// these, so it doubles as the "this one is resizable" affordance.
  static bool _isResizableRole(String? role) =>
      role == 'system-seed' || role == 'system-data';

  /// A single partition in the visualization: a pastel tile, sized
  /// proportionally by its caller. The entire tile is tappable for resizable
  /// partitions (system-seed / system-data); the pencil icon is kept as the
  /// "this one is resizable" marker but dimmed so it does not compete with the
  /// tile itself for attention.
  Widget _buildPartitionTile(
    BuildContext context,
    Map<String, dynamic> item,
    String volumeName,
  ) {
    final theme = Theme.of(context);
    final role = item['role'];
    final double size = item['size'];
    final String name = item['name'] ?? 'Unnamed';
    final bool resizable = _isResizableRole(role);
    final textScaler = MediaQuery.textScalerOf(context);
    final String tooltip = _partitionTooltipText(item['raw'], size);

    // The tile is sized proportionally by the caller. We measure the label
    // against the real available width and only draw it when it fits on a
    // single line; otherwise the tile degrades to a bare color stripe so very
    // small partitions are not squeezed into unreadable text. The tooltip
    // always carries the full data either way.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0;

        final TextPainter painter = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(
              color: _tileTextColor(theme),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout(maxWidth: double.infinity);
        // Show the name only if its natural (unwrapped) single-line width fits
        // the tile; otherwise render a bare color stripe (the tooltip still
        // carries all data). Laying out with an infinite max width measures the
        // label's true single-line width instead of letting it wrap to the tile
        // (which would make the width check a tautology).
        final bool fits = availWidth > 0 && painter.width <= availWidth;

        final Container box = Container(
          height: 78,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: _getPartitionColor(role, size),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.dividerColor, width: 0.5),
          ),
          child: fits
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          // Partition name, centered.
                          Center(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: _tileTextColor(theme),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // "Resizable" marker: the only hint about which
                          // partitions can be resized, dimmed so the whole
                          // tile reads as the tap affordance.
                          if (resizable)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                Icons.edit,
                                size: 18,
                                // 45% white: visible on the pastel fill, but
                                // clearly a secondary marker, not a button.
                                color:
                                    Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _formatSize(size),
                      style: TextStyle(
                        color: _tileTextColor(theme),
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : null,
        );

        final Widget withTooltip = Tooltip(message: tooltip, child: box);

        if (!resizable) {
          return withTooltip;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              _showPartitionSizeEditor(context, name, size, volumeName),
          child: withTooltip,
        );
      },
    );
  }

  /// Human-readable, all-fields description of a partition, used as the
  /// tooltip so the full data is available even when the label is hidden on a
  /// very small (bare-stripe) tile. [raw] is the original yaml structure
  /// entry for this partition.
  String _partitionTooltipText(Map<dynamic, dynamic> raw, double sizeInBytes) {
    final buffer = StringBuffer();
    void line(String key, dynamic value) {
      if (value == null) return;
      final String v = value.toString();
      if (v.isEmpty) return;
      buffer.writeln('$key: $v');
    }

    line('name', raw['name']);
    line('role', raw['role']);
    line('type', raw['type']);
    if (raw['size'] != null) {
      buffer.writeln('size: ${_formatSize(sizeInBytes)}');
    }
    line('offset', raw['offset']);
    line('filesystem', raw['filesystem']);
    line('min-size', raw['min-size']);
    line('label', raw['label']);

    final update = raw['update'];
    if (update is Map && update.isNotEmpty) {
      final parts = <String>[];
      for (final e in update.entries) {
        parts.add('${e.key} ${e.value}');
      }
      buffer.writeln('update: ${parts.join(', ')}');
    }

    final content = raw['content'];
    if (content is List && content.isNotEmpty) {
      final targets = <String>[];
      for (final c in content) {
        if (c is Map && c['target'] != null) {
          targets.add(c['target'].toString());
        }
      }
      if (targets.isNotEmpty) {
        // One target per line so a long content list cannot produce a single
        // very wide tooltip line (which could exceed the app window width).
        buffer.writeln('content:');
        for (final t in targets) {
          buffer.writeln('  - $t');
        }
      } else {
        buffer.writeln(
            'content: ${content.length} entr${content.length == 1 ? "y" : "ies"}');
      }
    }

    return buffer.toString().trimRight();
  }

  /// Opens the size editor for a resizable partition and refreshes the view
  /// once it reports a change.
  void _showPartitionSizeEditor(
    BuildContext context,
    String partitionName,
    double currentSize,
    String volumeName,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return PartitionSizeEditor(
          partitionName: partitionName,
          currentSize: _formatSize(currentSize),
          filePath: widget.filePath,
          volumeName: volumeName,
          onSave: (newSize) {
            // The dialog handles saving, so we just close it.
            if (widget.refreshCallback != null) {
              widget.refreshCallback!();
            }
            Navigator.of(context).pop();
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
          onStatusUpdate: (message) {
            if (widget.onStatusUpdate != null) {
              widget.onStatusUpdate!(message);
            } else if (widget.refreshCallback != null) {
              // Fallback to refresh if no status update callback.
              widget.refreshCallback!();
            }
          },
          onPartitionChanged: () {
            // Trigger refresh when partition is changed.
            if (widget.refreshCallback != null) {
              widget.refreshCallback!();
            }
          },
        );
      },
    );
  }

  /// Text color for a partition tile: white on dark pastel fills, dark text
  /// on light pastel fills, so the label stays legible in both light and dark
  /// mode regardless of the role color.
  Color _tileTextColor(ThemeData theme) =>
      (theme.brightness == Brightness.dark)
          ? Colors.white
          : const Color(0xFF262626);

  double _parseSize(dynamic size) {
    if (size == null) return 0;

    // Convert to string first if it's not already
    String sizeStr = size.toString();

    if (sizeStr.endsWith('M')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0) * 1024 * 1024;
    } else if (sizeStr.endsWith('G')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0) * 1024 * 1024 * 1024;
    } else if (sizeStr.endsWith('K')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0) * 1024;
    } else {
      // For sizes without units (like 440), treat as bytes
      return double.tryParse(sizeStr) ?? 0;
    }
  }

  String _formatSize(double sizeInBytes) {
    if (sizeInBytes >= 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
    } else if (sizeInBytes >= 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)}M';
    } else if (sizeInBytes >= 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)}K';
    } else {
      return '${sizeInBytes.toStringAsFixed(0)}B';
    }
  }

  Color _getPartitionColor(String? role, double sizeInBytes) {
    // Define pastel colors for each role
    Map<String, Color> roleColors = {
      'system-seed': const Color(0xFF81C784), // Light green (pastel)
      'system-boot': const Color(0xFF64B5F6), // Light blue (pastel)
      'system-save': const Color(0xFFBA68C8), // Light purple (pastel)
      'system-data': const Color(0xFFB39DDB), // Light purple (pastel)
    };
    // If we have a role, use the role-based color and adjust intensity based on size
    if (role != null && roleColors.containsKey(role)) {
      Color baseColor = roleColors[role]!;

      // Adjust intensity based on size (larger partitions = darker colors for better contrast)
      double intensity = _calculateIntensity(sizeInBytes);

      // Return the color with adjusted brightness
      return _adjustColorBrightness(baseColor, intensity);
    }

    // For partitions without roles, use a size-based color gradient
    return _getSizeBasedColor(sizeInBytes);
  }

  double _calculateIntensity(double sizeInBytes) {
    // Define reasonable size ranges to map to intensity
    const double smallThreshold = 1024 * 1024; // 1MB
    const double mediumThreshold = 1024 * 1024 * 1024; // 1GB

    if (sizeInBytes < smallThreshold) {
      return 0.8; // Light color for small partitions
    } else if (sizeInBytes < mediumThreshold) {
      return 0.6; // Medium color for medium partitions
    } else {
      return 0.4; // Darker color for large partitions
    }
  }

  Color _adjustColorBrightness(Color color, double intensity) {
    // Create a simple brightness adjustment by modifying RGB values directly
    int red = (color.r * 255.0 * intensity).round().clamp(0, 255);
    int green = (color.g * 255.0 * intensity).round().clamp(0, 255);
    int blue = (color.b * 255.0 * intensity).round().clamp(0, 255);

    return Color.fromARGB((color.a * 255.0).round().clamp(0, 255), red, green, blue);
  }

  Color _getSizeBasedColor(double sizeInBytes) {
    // Create a color gradient based on size using simple thresholds
    const double smallThreshold = 1024 * 1024; // 1MB
    const double mediumThreshold = 1024 * 1024 * 1024; // 1GB

    if (sizeInBytes < smallThreshold) {
      // Very small partitions - light blue (pastel)
      return const Color(0xFF90CAF9); // Light blue
    } else if (sizeInBytes < mediumThreshold) {
      // Medium partitions - medium blue (pastel)
      return const Color(0xFF64B5F6); // Blue
    } else {
      // Large partitions - dark blue (but still pastel-like)
      return const Color(0xFF1976D2); // Darker blue
    }
  }
}
