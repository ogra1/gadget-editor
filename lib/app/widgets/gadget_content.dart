import 'package:flutter/material.dart';

import 'package:gadget_editor/services/gadget_yaml_service.dart';

import 'gadget_section.dart';
import 'gadget_volumes.dart';
import 'simple_connections_editor.dart';
import 'simple_defaults_editor.dart';
import 'simple_kernel_cmdline_editor.dart';

/// Displays the content of a gadget.yaml.
///
/// The widget is a pure viewer: it renders the sections of the current
/// document and forwards user actions (delete, add) to the [GadgetYaml]
/// service, which performs the format-preserving YAML edits on disk.
///
/// Delete callbacks from the section widgets are section-aware:
///   * Defaults      -> (data, keyIndex)          key = defaults[keyIndex]
///   * Connections   -> (data, listIndex)
///   * Boot Options  -> (data, (section, index))  section in allow/append/remove
class GadgetContent extends StatefulWidget {
  final String? content;
  final String? filePath;
  final Function(String)? onContentChanged; // Add callback for content changes
  final Function(String) onStatusUpdate; // Add status update callback

  const GadgetContent({
    super.key,
    required this.content,
    this.filePath,
    this.onContentChanged,
    required this.onStatusUpdate,
  });

  @override
  State<GadgetContent> createState() => _GadgetContentState();
}

class _GadgetContentState extends State<GadgetContent> {
  Map<String, dynamic> _yamlData = const {};
  String _error = '';

  @override
  void initState() {
    super.initState();
    // The first build may already carry content (e.g. right after a
    // download), so parse eagerly; didUpdateWidget covers later changes.
    _parseContent();
  }

  @override
  void didUpdateWidget(covariant GadgetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When widget updates with new content, re-parse it
    if (widget.content != oldWidget.content) {
      _parseContent();
    }
  }

  void _parseContent() {
    // Handle null or empty content
    if (widget.content == null || widget.content!.isEmpty) {
      setState(() {
        _error = 'No gadget content to display';
      });
      return;
    }

    try {
      final yaml = GadgetYaml.fromContent(widget.content!);
      // The display widgets are written against YamlMap/YamlList types, so
      // hand them the shallow view (String keys, Yaml values).
      _yamlData = yaml.view();
      _error = '';
    } catch (e) {
      setState(() {
        _error = 'Error parsing YAML: $e';
        _yamlData = const {};
      });
      return;
    }
    if (mounted) setState(() {});
  }

  // Re-read the backing file and refresh the rendered sections.
  void _refreshContentFromFile() {
    final filePath = widget.filePath;
    if (filePath == null) {
      _parseContent();
      return;
    }
    try {
      final yaml = GadgetYaml.fromFile(filePath);
      widget.onContentChanged?.call(yaml.toYaml());
      _yamlData = yaml.view();
      _error = '';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error reading file: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) {
      return Center(
        child: Text(_error),
      );
    }

    // If we have no data but no error, show empty state
    if (_yamlData.isEmpty) {
      return const Center(
        child: Text('No gadget content to display'),
      );
    }

    final volumes = _yamlData['volumes'];
    final defaults = _yamlData['defaults'];
    final connections = _yamlData['connections'];
    final kernelCmdline = _yamlData['kernel-cmdline'];
    final extras = <String, dynamic>{};
    final mainKeys = ['volumes', 'schema', 'bootloader', 'defaults', 'connections', 'kernel-cmdline'];
    for (var key in _yamlData.keys) {
      if (!mainKeys.contains(key)) {
        extras[key] = _yamlData[key];
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
            filePath: widget.filePath,
            refreshCallback: _refreshContentFromFile,
            onStatusUpdate: widget.onStatusUpdate,
          ),
          const SizedBox(height: 16),

          // Defaults Section
          GadgetSection(
            title: 'Defaults',
            data: defaults,
            onEdit: () {
              _showEditorDialog(context, 'Defaults', defaults, (data) {
                // Refresh the content after saving
                _refreshContentFromFile();
              });
            },
            onDelete: (data, index) {
              _deleteDefault(data, index);
            },
          ),
          const SizedBox(height: 16),

          // Connections Section
          GadgetSection(
            title: 'Connections',
            data: connections,
            onEdit: () {
              _showEditorDialog(context, 'Connections', connections, (data) {
                // Refresh the content after saving
                _refreshContentFromFile();
              });
            },
            onDelete: (data, index) {
              _deleteConnection(data, index);
            },
          ),
          const SizedBox(height: 16),

          // Kernel Cmdline Section
          GadgetSection(
            title: 'Boot Options',
            data: kernelCmdline,
            onEdit: () {
              _showEditorDialog(context, 'Boot Options', kernelCmdline, (data) {
                // Refresh the content after saving
                _refreshContentFromFile();
              });
            },
            onDelete: (data, index) {
              _deleteKernelCmdline(data, index);
            },
          ),
          const SizedBox(height: 16),

          // Show the Extras section whenever the document has keys the editor
          // does not have a dedicated section for. It is not architecture-
          // dependent.
          if (extras.isNotEmpty)
            GadgetSection(
              title: 'Extras (unknown keys)',
              data: extras,
            ),
        ],
      ),
    );
  }

  /// Removes the defaults entry at [index] (the key of the card that was
  /// deleted, not necessarily index 0 in the map).
  void _deleteDefault(dynamic data, Object? index) {
    if (index is! int) {
      _status('Error deleting default: unknown position');
      return;
    }
    final defaults = _yamlData['defaults'];
    if (defaults is! Map) {
      _status('Default deletion not implemented for this structure');
      return;
    }
    final keys = defaults.keys.map((k) => k.toString()).toList();
    if (index < 0 || index >= keys.length) {
      _status('Error deleting default: no entry at index $index');
      return;
    }
    final key = keys[index];
    _mutate(
      (yaml) => yaml.removeDefault(key),
      'Default deleted successfully',
      'Error deleting default: ',
    );
  }

  /// Removes the [index]th entry of the top-level connections list.
  void _deleteConnection(dynamic data, Object? index) {
    if (index is! int) {
      _status('Error deleting connection: unknown position');
      return;
    }
    if (data is! List || index < 0 || index >= data.length) {
      _status('Error deleting connection: no entry at index $index');
      return;
    }
    _mutate(
      (yaml) => yaml.removeConnection(index),
      'Connection deleted successfully',
      'Error deleting connection: ',
    );
  }

  /// Removes one kernel-cmdline entry. The section widget reports the item
  /// as (section, index) so the right list is targeted.
  void _deleteKernelCmdline(dynamic data, Object? index) {
    if (index is! List ||
        index.length != 2 ||
        index[0] is! String ||
        index[1] is! int) {
      _status('Error deleting kernel parameter: unknown position');
      return;
    }
    final section = index[0] as String;
    final itemIndex = index[1] as int;
    _mutate(
      (yaml) => yaml.removeKernelCmdlineItem(section, itemIndex),
      'Kernel parameter deleted successfully',
      'Error deleting kernel parameter: ',
    );
  }

  /// Runs [edit] against a fresh [GadgetYaml] loaded from the backing file,
  /// persists it and refreshes the rendered content. All error reporting and
  /// the read-edit-write ritual lives here so the individual delete
  /// handlers only describe *what* to change.
  void _mutate(
    void Function(GadgetYaml yaml) edit,
    String successMessage,
    String errorPrefix,
  ) {
    final filePath = widget.filePath;
    if (filePath == null) {
      _status('$errorPrefix no file loaded');
      return;
    }
    try {
      final yaml = GadgetYaml.fromFile(filePath);
      edit(yaml);
      yaml.save();
      _status(successMessage);
      _refreshContentFromFile();
    } on GadgetYamlException catch (e) {
      _status('$errorPrefix${e.message}');
    } catch (e) {
      _status('$errorPrefix$e');
    }
  }

  void _status(String message) => widget.onStatusUpdate(message);

  void _showEditorDialog(BuildContext context, String title, dynamic data, Function(dynamic) onSave) {
    Widget editorWidget;

    switch (title) {
      case 'Defaults':
        editorWidget = SimpleDefaultsEditor(
          defaults: data,
          filePath: widget.filePath,
          onSave: (updatedData) {
            Navigator.of(context).pop();
            // Refresh the content after saving
            _refreshContentFromFile();
            onSave(updatedData);
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
          onStatusUpdate: widget.onStatusUpdate,
        );
        break;
      case 'Connections':
        editorWidget = SimpleConnectionsEditor(
          connections: data,
          filePath: widget.filePath,
          onSave: (updatedData) {
            Navigator.of(context).pop();
            // Refresh the content after saving
            _refreshContentFromFile();
            onSave(updatedData);
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
          onStatusUpdate: widget.onStatusUpdate,
        );
        break;
      case 'Boot Options':
        editorWidget = SimpleKernelCmdlineEditor(
          kernelCmdline: data,
          filePath: widget.filePath,
          onSave: (updatedData) {
            Navigator.of(context).pop();
            // Refresh the content after saving
            _refreshContentFromFile();
            onSave(updatedData);
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
          onStatusUpdate: widget.onStatusUpdate,
        );
        break;
      default:
        editorWidget = const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Editor for this section is not implemented yet.'),
        );
    }

    // Make dialogs fit content size with 50% width instead of 80%
    double dialogWidth = MediaQuery.of(context).size.width * 0.5;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Change the dialog title to be singular
        String singularTitle = title;
        if (title == 'Connections') {
          singularTitle = 'Connection';
        }
        // Special handling for defaults editor caption
        if (title == 'Defaults') {
          return AlertDialog(
            title: const Text('Add new Configuration for Snap'),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: editorWidget,
              ),
            ),
          );
        }
        if (title == 'Boot Options') {
          singularTitle = 'Boot Option';
        }
        return AlertDialog(
          title: Text('Add new $singularTitle'),
          content: SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              child: editorWidget,
            ),
          ),
        );
      },
    );
  }
}
