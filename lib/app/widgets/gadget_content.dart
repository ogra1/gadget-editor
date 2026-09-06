import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'gadget_volumes.dart';
import 'gadget_section.dart';
import 'simple_volume_editor.dart';
import 'simple_defaults_editor.dart';
import 'simple_connections_editor.dart';

class GadgetContent extends StatelessWidget {
  final String? content;
  final bool isAmd64; // Add this parameter
  const GadgetContent({
    super.key,
    required this.content,
    required this.isAmd64, // Add this parameter
  });

  @override
  Widget build(BuildContext context) {
    if (content == null || content!.isEmpty) {
      return const Center(
        child: Text('No gadget content to display'),
      );
    }
    try {
      final yaml = loadYaml(content!);
      final volumes = yaml['volumes'];
      final schema = yaml['schema'];
      final bootloader = yaml['bootloader'];
      final defaults = yaml['defaults'];
      final connections = yaml['connections'];
      final extras = <String, dynamic>{};
      final allKeys = yaml.keys.toList();
      final mainKeys = ['volumes', 'schema', 'bootloader', 'defaults', 'connections'];
      for (var key in allKeys) {
        if (!mainKeys.contains(key)) {
          extras[key] = yaml[key];
        }
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Volumes Section
            GadgetVolumesSection(
              volumes: volumes,
              onEdit: () {
                _showEditorDialog(context, 'Volumes', volumes, (data) {
                  // In a real implementation, this would save the data
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Volumes would be saved in a real implementation')),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            // Defaults Section
            GadgetSection(
              title: 'Defaults',
              data: defaults,
              onEdit: () {
                _showEditorDialog(context, 'Defaults', defaults, (data) {
                  // In a real implementation, this would save the data
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Defaults would be saved in a real implementation')),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            // Connections Section
            GadgetSection(
              title: 'Connections',
              data: connections,
              onEdit: () {
                _showEditorDialog(context, 'Connections', connections, (data) {
                  // In a real implementation, this would save the data
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Connections would be saved in a real implementation')),
                  );
                });
              },
            ),
            const SizedBox(height: 16),

            // Only show Extras section for non-amd64 platforms
            if (!isAmd64 && extras.isNotEmpty)
              GadgetSection(
                title: 'Extras',
                data: extras,
              ),
          ],
        ),
      );
    } catch (e) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            content ?? '',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
      );
    }
  }

  void _showEditorDialog(BuildContext context, String title, dynamic data, Function(dynamic) onSave) {
    Widget editorWidget;

    switch (title) {
      case 'Volumes':
        editorWidget = SimpleVolumeEditor(
          volumes: data,
          onSave: (updatedData) {
            Navigator.of(context).pop();
            onSave(updatedData);
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        );
        break;
      case 'Defaults':
        editorWidget = SimpleDefaultsEditor(
          defaults: data,
          onSave: (updatedData) {
            Navigator.of(context).pop();
            onSave(updatedData);
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        );
        break;
      case 'Connections':
        editorWidget = SimpleConnectionsEditor(
          connections: data,
          onSave: (updatedData) {
            Navigator.of(context).pop();
            onSave(updatedData);
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        );
        break;
      default:
        editorWidget = Container(
          padding: const EdgeInsets.all(16),
          child: const Text('Editor for this section is not implemented yet.'),
        );
    }
    
    // Make dialogs slimmer (half the size)
    double dialogWidth = MediaQuery.of(context).size.width * 0.6; // 60% instead of 100%
    double dialogHeight = 400; // Half of the original height
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Change the dialog title to be singular
        String singularTitle = title;
        if (title == 'Connections') {
          singularTitle = 'Connection';
        }
        return AlertDialog(
          title: Text('$singularTitle Editor'),
          content: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: editorWidget,
          ),
        );
      },
    );
  }
}
