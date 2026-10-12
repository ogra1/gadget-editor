import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'package:yaml/yaml.dart';

class GadgetSection extends StatelessWidget {
  final String title;
  final dynamic data;
  final VoidCallback? onEdit;
  final bool showEditButton;
  final Function(dynamic, Object?)? onDelete; // Add delete callback (kernel-cmdline passes [section, index])
  final int? sectionIndex; // Add section index for tracking

  const GadgetSection({
    super.key,
    required this.title,
    required this.data,
    this.onEdit,
    this.showEditButton = true,
    this.onDelete,
    this.sectionIndex,
  });

  /// Section-specific identity icon. The three editable sections get
  /// distinct Yaru glyphs so they are distinguishable at a glance; anything
  /// else (e.g. Extras) falls back to a neutral "settings" outline.
  static IconData sectionIconFor(String title) {
    switch (title) {
      case 'Defaults':
        return YaruIcons.settings;
      case 'Connections':
        return YaruIcons.insert_link;
      case 'Boot Options':
        return YaruIcons.terminal;
      default:
        return YaruIcons.gear;
    }
  }

  /// Caption shown in the empty state, per section.
  String get _emptyCaption {
    switch (title) {
      case 'Defaults':
        return 'No defaults yet. Add snap configuration entries.';
      case 'Connections':
        return 'No connections yet. Define snap plug/slot connections.';
      case 'Boot Options':
        return 'No boot options yet. Add kernel commandline options.';
      default:
        return 'No data';
    }
  }

  /// Header row shared by the empty and populated states: a tinted icon chip
  /// plus the title, with the add control on the right when applicable.
  ///
  /// [showAddButton] is false in the empty state, where the drop-zone's
  /// "Add …" button already provides the add affordance (the header + would
  /// be redundant).
  Widget _buildHeader(BuildContext context, {bool showAddButton = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            sectionIconFor(title),
            size: 20,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (showAddButton && showEditButton && onEdit != null)
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: onEdit,
            tooltip: 'Add $title',
          ),
      ],
    );
  }

  /// Dashed rounded-rectangle border used by the empty state. Drawn with a
  /// CustomPainter so no extra package is needed.
  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final VoidCallback? addOnEdit =
        (showEditButton && onEdit != null) ? onEdit : null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CustomPaint(
        // Key so tests can assert on the dashed drop-zone specifically
        // (Yaru's theming injects its own CustomPaints into the tree).
        key: const ValueKey('gadget-section-dashed-zone'),
        painter: _DashedBorder(
          color: scheme.outline,
          radius: 10,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                sectionIconFor(title),
                size: 30,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 10),
              Text(
                _emptyCaption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (addOnEdit != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: addOnEdit,
                  icon: const Icon(YaruIcons.plus, size: 18),
                  label: Text('Add $title'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        data == null || (data is YamlMap && data.isEmpty) || (data is List && data.isEmpty);

    final Widget body = isEmpty
        ? _buildEmptyState(context)
        : _buildSectionContent(context, data);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // In the empty state the drop-zone button is the add affordance,
            // so hide the header's + to avoid a duplicate.
            _buildHeader(context, showAddButton: !isEmpty),
            body,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent(BuildContext context, dynamic data) {
    if (data == null) {
      return const Text('No data');
    }

    // Special handling for connections to match the editor style
    if (title == 'Connections') {
      return _buildConnectionsContent(context, data);
    }

    // Special handling for defaults to show hierarchical structure
    if (title == 'Defaults') {
      return _buildDefaultsContent(context, data);
    }

    // Special handling for kernel cmdline to group by allow/append/remove
    if (title == 'Boot Options') {
      return _buildKernelCmdlineContent(context, data);
    }

    // Handle single key-value maps specially
    if (data is Map && data.length == 1) {
      // For single key-value pairs, display them cleanly on one line
      final entries = data.entries.toList();
      final entry = entries[0];
      final key = entry.key;
      final value = entry.value;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$key:',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8), // Space between key and value
          Text('$value'),
        ],
      );
    }

    if (data is YamlMap) {
      if (data.isEmpty) {
        return const Text('No data');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: data.entries.map((entry) {
          final key = entry.key;
          final value = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$key:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // Add indentation to the content
              Container(
                margin: const EdgeInsets.only(left: 16), // This creates the indentation
                child: _buildValueWidget(context, value),
              ),
              const SizedBox(height: 12),
            ],
          );
        }).toList(),
      );
    }

    if (data is List) {
      if (data.isEmpty) {
        return const Text('No data');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: data.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Item $index:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // Add indentation to the content
              Container(
                margin: const EdgeInsets.only(left: 16), // This creates the indentation
                child: _buildValueWidget(context, item),
              ),
              const SizedBox(height: 12),
            ],
          );
        }).toList(),
      );
    }

    // Handle primitive values
    return Text('$data');
  }

  Widget _buildKernelCmdlineContent(BuildContext context, dynamic data) {
    if (data == null) {
      return const Text('No kernel cmdline defined.');
    }

    // Handle the case where data is a string (raw YAML) - this can happen after deletion
    // We need to parse it properly to avoid showing raw YAML
    if (data is String) {
      try {
        // Try to parse the string as YAML
        final parsedData = loadYaml(data);
        if (parsedData is YamlMap) {
          // If we successfully parsed it, render it properly
          return _buildKernelCmdlineContent(context, parsedData);
        } else {
          // If it's not a YamlMap, display it as a formatted string
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              data,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          );
        }
      } catch (e) {
        // If parsing fails, display as raw text
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            data,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        );
      }
    }

    if (data is YamlMap && data.isEmpty) {
      return const Text('No kernel cmdline defined.');
    }

    // For kernel-cmdline, we want to group by allow/append/remove
    if (data is YamlMap) {
      // Extract the groups - handle both List and String values properly
      final allowList = data['allow'] is List ? data['allow'] as List : [];
      final appendList = data['append'] is List ? data['append'] as List : [];
      final removeList = data['remove'] is List ? data['remove'] as List : [];

      // Only show groups that have content
      final groups = <String, List<dynamic>>{};
      if (allowList.isNotEmpty) groups['allow'] = allowList;
      if (appendList.isNotEmpty) groups['append'] = appendList;
      if (removeList.isNotEmpty) groups['remove'] = removeList;

      if (groups.isEmpty) {
        return const Text('No kernel cmdline options defined.');
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var group in groups.entries)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.key.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Display each item in the group
                    for (int i = 0; i < group.value.length; i++)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                border: Border.all(color: Theme.of(context).dividerColor),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${group.value[i]}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          if (onDelete != null)
                            IconButton(
                              icon: const Icon(Icons.delete, size: 16),
                              onPressed: () {
                                _showDeleteConfirmationDialog(context, 'Kernel parameter', [group.key, i]);
                              },
                              tooltip: 'Delete parameter',
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    // Handle other kernel-cmdline structures - ensure we don't show raw data
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$data',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildConnectionsContent(BuildContext context, dynamic data) {
    // For connections, we want to display them in the same styled format as the editor
    if (data == null) {
      return const Text('No connections defined.');
    }

    if (data is List && data.isEmpty) {
      return const Text('No connections defined.');
    }

    // Special handling for connections - we'll build a custom display
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // If it's a list of connections, show them
        if (data is List && data.isNotEmpty)
          ...data.asMap().entries.map((entry) {
            final index = entry.key;
            final connection = entry.value;

            // Build connection display with proper styling and delete button
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Plug line
                          Row(
                            children: [
                              Container(
                                width: 40, // Fixed width to ensure alignment
                                alignment: Alignment.centerLeft,
                                child: const Text('Plug: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Expanded(
                                child: Text(
                                  // Combined on-disk format: <snap id>:<interface>.
                                  connection['plug']?.toString() ?? 'N/A',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          ),
                          // Slot line - only show if slot is defined
                          if (connection['slot'] != null && connection['slot'] != '')
                            Row(
                              children: [
                                Container(
                                  width: 40, // Fixed width to ensure alignment
                                  alignment: Alignment.centerLeft,
                                  child: const Text('Slot: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                Expanded(
                                  child: Text(
                                    connection['slot'].toString(),
                                    style: const TextStyle(fontFamily: 'monospace'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete, size: 16),
                        onPressed: () {
                          _showDeleteConfirmationDialog(context, 'Connection', index);
                        },
                        tooltip: 'Delete connection',
                      ),
                  ],
                ),
              ),
            );
          }).toList()
        else if (data is YamlMap)
          // If it's a map structure, handle differently
          const Text('Connection data in map format')
        else
          // If it's a simple value, just display it
          Text('$data'),
      ],
    );
  }

  Widget _buildDefaultsContent(BuildContext context, dynamic data) {
    if (data == null) {
      return const Text('No defaults defined.');
    }

    if (data is YamlMap && data.isEmpty) {
      return const Text('No defaults defined.');
    }

    // For defaults, we want to display the hierarchical structure in cards
    if (data is YamlMap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.entries.toList().asMap().entries.map((entryWithIndex) {
          final key = entryWithIndex.value.key;
          final value = entryWithIndex.value.value;
          final entryIndex = entryWithIndex.key;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display the main key (snap ID or system) with improved styling
                        Row(
                          children: [
                            const Text('Snap: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('$key', style: const TextStyle(fontWeight: FontWeight.normal)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Display the nested content - this is where the issue was
                        _buildValueWidget(context, value),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 16),
                      onPressed: () {
                        _showDeleteConfirmationDialog(context, 'Default', entryIndex);
                      },
                      tooltip: 'Delete default',
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    // Handle other default structures
    return _buildValueWidget(context, data);
  }

  Widget _buildValueWidget(BuildContext context, dynamic value) {
    if (value == null) {
      return const Text('null');
    }

    // Handle multiline strings (like the LXD example with |)
    if (value is String && value.contains('\n')) {
      // For multiline values, we'll display them in a code-like format
      // The issue was that we were using a white background with white text
      // Fixing this by using proper text color and background
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, // Use theme-appropriate background
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black, // Use theme text color
          ),
        ),
      );
    }

    if (value is YamlMap) {
      if (value.isEmpty) {
        return const Text('(empty)');
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: value.entries.map((entry) {
          final key = entry.key;
          final nestedValue = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$key:',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                margin: const EdgeInsets.only(left: 16),
                child: _buildValueWidget(context, nestedValue),
              ),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      );
    }

    if (value is List) {
      if (value.isEmpty) {
        return const Text('(empty)');
      }

      return Container(
        margin: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: value.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$index: '),
                Expanded(
                  child: _buildValueWidget(context, item),
                ),
              ],
            );
          }).toList(),
        ),
      );
    }

    // Handle primitive values
    return Text('$value');
  }

  void _showDeleteConfirmationDialog(BuildContext context, String title, Object? index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete $title'),
          content: Text('Are you sure you want to delete this $title?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Call the delete callback with the correct parameters
                if (onDelete != null) {
                  onDelete!(data, index);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

/// Draws a dashed rounded-rectangle stroke.
class _DashedBorder extends CustomPainter {
  static const double _strokeWidth = 1.4;
  static const List<double> _dash = [6.0, 5.0];

  final Color color;
  final double radius;

  const _DashedBorder({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius.clamp(0.0, size.shortestSide / 2);
    const half = _strokeWidth / 2;
    final right = size.width - half;
    final bottom = size.height - half;

    // Perimeter as (start, end) straight segments plus the four corner arcs.
    final segments = <List<Offset>>[
      [const Offset(half, half), Offset(right - r, half)], // top edge
      [Offset(right, half + r), Offset(right, bottom - r)], // right edge
      [Offset(right - r, bottom), Offset(half + r, bottom)], // bottom edge
      [Offset(half, bottom - r), Offset(half, half + r)], // left edge
    ];
    final arcs = <Rect>[
      Rect.fromLTWH(right - 2 * r, half, 2 * r, 2 * r), // top-right
      Rect.fromLTWH(half, bottom - 2 * r, 2 * r, 2 * r), // bottom-left
    ];

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    var gap = false; // whether the next bit of path is a gap
    final path = Path();

    void dashSegment(Offset a, Offset b, double len) {
      for (var t = 0.0; t < len; ) {
        final segLen = (gap ? _dash[1] : _dash[0]).clamp(0.0, len - t);
        if (!gap) {
          final a2 = Offset.lerp(a, b, t / len)!;
          final b2 = Offset.lerp(a, b, (t + segLen) / len)!;
          path.moveTo(a2.dx, a2.dy);
          path.lineTo(b2.dx, b2.dy);
        }
        t += segLen;
        gap = !gap;
      }
    }

    for (final seg in segments) {
      dashSegment(seg[0], seg[1], (seg[0] - seg[1]).distance);
    }
    // Corner arcs (each quarter of a 2r-diameter circle).
    for (final rect in arcs) {
      final quarter = 3.141592653589793 * r / 2;
      // Walk each arc in small steps so the dash pattern follows the curve.
      const steps = 12;
      for (var i = 0; i < steps; i++) {
        final t0 = i / steps * quarter;
        final t1 = (i + 1) / steps * quarter;
        final p0 = _arcPoint(rect, t0);
        final p1 = _arcPoint(rect, t1);
        dashSegment(p0, p1, (p0 - p1).distance);
      }
    }
    canvas.drawPath(path, paint);
  }

  // Point on the quarter-circle centred in [rect] at [t] radians (0..pi/2)
  // measured from the top, clockwise.
  Offset _arcPoint(Rect rect, double t) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rr = rect.width / 2;
    return Offset(cx + rr * math.sin(t), cy - rr * math.cos(t));
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) =>
      old.color != color || old.radius != radius;
}
