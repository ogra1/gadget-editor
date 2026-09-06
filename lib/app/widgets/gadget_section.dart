import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'simple_connections_editor.dart'; // Import our connection editor

class GadgetSection extends StatelessWidget {
  final String title;
  final dynamic data;
  final VoidCallback? onEdit;
  final bool showEditButton;

  const GadgetSection({
    super.key,
    required this.title,
    required this.data,
    this.onEdit,
    this.showEditButton = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data == null || (data is YamlMap && data.isEmpty) || (data is List && data.isEmpty)) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (showEditButton && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    onPressed: onEdit,
                    tooltip: 'Edit $title',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (title == 'Defaults')
              const Text('No defaults defined. Click the edit icon to add defaults.')
            else if (title == 'Connections')
              const Text('No connections defined. Click the edit icon to add connections.')
            else
              const Text('No data'),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (showEditButton && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    onPressed: onEdit,
                    tooltip: 'Edit $title',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSectionContent(context, data),
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
      return _buildConnectionsContent(data);
    }
    
    // Special handling for defaults to show hierarchical structure
    if (title == 'Defaults') {
      return _buildDefaultsContent(context, data);
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

  Widget _buildConnectionsContent(dynamic data) {
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
          ...data.map((connection) {
            // Build connection display with proper styling
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
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
                            // Handle connections that may be in combined format
                            connection['plug'] != null 
                              ? '${connection['plugSnapId'] != null && connection['plugSnapId'] != '' ? '${connection['plugSnapId']!}:' : ''}${connection['plug']}'
                              : 'N/A',
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
                              '${connection['slotSnapId'] != null && connection['slotSnapId'] != '' ? '${connection['slotSnapId']!}:' : ''}${connection['slot']}',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }).toList()
        else if (data is YamlMap)
          // If it's a map structure, handle differently
          Text('Connection data in map format')
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
        children: data.entries.map((entry) {
          final key = entry.key;
          final value = entry.value;
          
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
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
}
