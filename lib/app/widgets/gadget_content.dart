import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'gadget_volumes.dart';
import 'gadget_section.dart';
import 'simple_volume_editor.dart';
import 'simple_defaults_editor.dart';
import 'simple_connections_editor.dart';
import 'simple_kernel_cmdline_editor.dart';
import 'dart:io';
import 'package:gadget_editor/app/utils/yaml_serializer.dart';
import 'package:yaml_edit/yaml_edit.dart';

class GadgetContent extends StatefulWidget {
  final String? content;
  final bool isAmd64;
  final String? filePath;
  final Function(String)? onContentChanged; // Add callback for content changes
  final Function(String) onStatusUpdate; // Add status update callback
  const GadgetContent({
    super.key,
    required this.content,
    required this.isAmd64,
    this.filePath,
    this.onContentChanged,
    required this.onStatusUpdate,
  });

  @override
  State<GadgetContent> createState() => _GadgetContentState();
}

class _GadgetContentState extends State<GadgetContent> {
  late Map<String, dynamic> _yamlData;
  bool _isLoading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
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
      // Parse the YAML content
      final yaml = loadYaml(widget.content!);

      // Convert YamlMap to Map<String, dynamic> properly
      Map<String, dynamic> yamlMap;
      if (yaml is YamlMap) {
        // Convert YamlMap to regular Map<String, dynamic>
        yamlMap = {};
        for (var key in yaml.keys) {
          yamlMap[key.toString()] = yaml[key];
        }
      } else if (yaml is Map) {
        // Ensure the map has String keys
        yamlMap = {};
        for (var entry in yaml.entries) {
          yamlMap[entry.key.toString()] = entry.value;
        }
      } else {
        yamlMap = {};
      }

      setState(() {
        _yamlData = yamlMap;
        _error = '';
      });
    } catch (e) {
      // Handle parsing errors gracefully
      setState(() {
        _error = 'Error parsing YAML: $e';
        // Also try to display the raw content as fallback
        _yamlData = {};
      });
    }
  }

  // Re-parse the content after changes
  void _refreshContent() {
    _parseContent();
  }

  // Method to refresh content from file when needed
  Future<void> _refreshContentFromFile() async {
    if (widget.filePath != null) {
      try {
        final file = File(widget.filePath!);
        final content = await file.readAsString();
        // Update the widget's content and re-parse
        widget.onContentChanged?.call(content);
        _parseContent();
      } catch (e) {
        // Handle file reading errors
        setState(() {
          _error = 'Error reading file: $e';
        });
      }
    } else {
      _parseContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) {
      return Center(
        child: Text(_error),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If we have no data but no error, show empty state
    if (_yamlData.isEmpty) {
      return const Center(
        child: Text('No gadget content to display'),
      );
    }

    final volumes = _yamlData['volumes'];
    final schema = _yamlData['schema'];
    final bootloader = _yamlData['bootloader'];
    final defaults = _yamlData['defaults'];
    final connections = _yamlData['connections'];
    final kernelCmdline = _yamlData['kernel-cmdline'];
    final extras = <String, dynamic>{};
    final allKeys = _yamlData.keys.toList();
    final mainKeys = ['volumes', 'schema', 'bootloader', 'defaults', 'connections', 'kernel-cmdline'];
    for (var key in allKeys) {
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

          // Only show Extras section for non-amd64 platforms
          if (!widget.isAmd64 && extras.isNotEmpty)
            GadgetSection(
              title: 'Extras',
              data: extras,
            ),
        ],
      ),
    );
  }

  void _deleteDefault(dynamic data, int index) {
    // For defaults, we need to properly remove from the YAML structure
    if (data is YamlMap) {
      // Get all keys from the defaults map
      final keys = data.keys.toList();
      if (index < keys.length) {
        final keyToDelete = keys[index];

        // Use yaml_edit to properly remove the key from YAML structure
        if (widget.filePath != null) {
          // Inline the yaml_edit logic directly in _deleteDefault
          try {
            // Read the existing file content
            final file = File(widget.filePath!);
            final content = file.readAsStringSync();

            // Parse the existing YAML
            final yaml = loadYaml(content);

            // Create a YamlEditor instance to properly handle the YAML structure
            final yamlEditor = YamlEditor(content);

            // Remove the key from defaults section using yaml_edit's remove function
            if (yaml.containsKey('defaults') && yaml['defaults'] is YamlMap) {
              // Use yaml_edit's remove function to delete the specific key
              yamlEditor.remove(['defaults', keyToDelete]);

              // Check if the defaults section is now empty and remove it entirely if so
              final path = ['defaults'];
              final defaultsSection = yamlEditor.parseAt(path);
              if (defaultsSection is YamlMap) {
                if (defaultsSection.isEmpty) {
                  // Remove the entire defaults section if it's now empty
                  yamlEditor.remove(['defaults']);
                }
              } else if (defaultsSection is Map) {
                final defaultsSection = yaml['defaults'];
                if (defaultsSection.isEmpty) {
                  // Remove the entire defaults section if it's now empty
                  yamlEditor.remove(['defaults']);
                }
              }
            } else if (yaml.containsKey('defaults') && yaml['defaults'] is Map) {
              // Handle Map case
              yamlEditor.remove(['defaults', keyToDelete]);

              // Check if the defaults section is now empty and remove it entirely if so
              final defaultsSection = yaml['defaults'];
              if (defaultsSection is Map) {
                if (defaultsSection.isEmpty) {
                  // Remove the entire defaults section if it's now empty
                  yamlEditor.remove(['defaults']);
                }
              }
            }

            // Write back to file using yaml_editor's toString() method
            final newYamlString = yamlEditor.toString();

            // Write back to file
            file.writeAsStringSync(newYamlString);

            // Show success message via status bar
            widget.onStatusUpdate('Default deleted successfully');

            // Refresh content to reflect changes
            _refreshContentFromFile();

          } catch (e) {
            widget.onStatusUpdate('Error deleting default: $e');
          }
        } else {
          // Fallback for when no file path is provided
          setState(() {
            if (_yamlData.containsKey('defaults') && _yamlData['defaults'] is YamlMap) {
              final defaultsMap = _yamlData['defaults'] as YamlMap;
              // Create a new YamlMap without the deleted key to preserve YAML structure
              final newYamlMap = YamlMap();
              for (var key in defaultsMap.keys) {
                if (key != keyToDelete) {
                  newYamlMap[key] = defaultsMap[key];
                }
              }
              _yamlData['defaults'] = newYamlMap;
            }
          });

          // Show success message via status bar
          widget.onStatusUpdate('Default deleted successfully');

          // Refresh content to reflect changes
          _refreshContentFromFile();
        }
      }
    } else if (data is Map) {
      // Handle regular Map case
      final keys = data.keys.toList();
      if (index < keys.length) {
        final keyToDelete = keys[index];

        setState(() {
          if (_yamlData.containsKey('defaults') && _yamlData['defaults'] is Map) {
            final defaultsMap = _yamlData['defaults'] as Map<String, dynamic>;
            final mutableDefaults = Map<String, dynamic>.from(defaultsMap);
            mutableDefaults.remove(keyToDelete);
            _yamlData['defaults'] = mutableDefaults;
          }
        });

        // Show success message via status bar
        widget.onStatusUpdate('Default deleted successfully');

        // Save changes to file if filePath is provided
        if (widget.filePath != null) {
          _saveChangesToFile();
        }

        // Refresh content to reflect changes
        _refreshContentFromFile();
      }
    } else {
      // For other structures, show message via status bar
      widget.onStatusUpdate('Default deletion not implemented for this structure');
    }
  }

  void _deleteConnection(dynamic data, int index) {
    if (widget.filePath != null) {
      // Use yaml_edit to properly remove the connection from YAML structure
      try {
        // Read the existing file content
        final file = File(widget.filePath!);
        final content = file.readAsStringSync();

        // Parse the existing YAML
        final yaml = loadYaml(content);

        // Create a YamlEditor instance to properly handle the YAML structure
        final yamlEditor = YamlEditor(content);

        // Remove the connection at the specified index
        if (yaml.containsKey('connections') && yaml['connections'] is List) {
          // Use yaml_edit's remove function to delete the specific connection
          yamlEditor.remove(['connections', index]);

          // Check if the connections section is now empty and remove it entirely if so
          final connectionsSection = yamlEditor.parseAt(['connections']).value;
          if (connectionsSection is List && connectionsSection.isEmpty) {
            // Remove the entire connections section if it's now empty
            yamlEditor.remove(['connections']);
          }
        }

        // Write back to file using yaml_editor's toString() method
        final newYamlString = yamlEditor.toString();

        // Write back to file
        file.writeAsStringSync(newYamlString);

        // Show success message via status bar
        widget.onStatusUpdate('Connection deleted successfully');

        // Refresh content to reflect changes
        _refreshContentFromFile();

      } catch (e) {
        widget.onStatusUpdate('Error deleting connection: $e');
      }
    } else {
      // Fallback for when no file path is provided
      setState(() {
        if (_yamlData.containsKey('connections') && _yamlData['connections'] is List) {
          final connectionsList = List.from(_yamlData['connections']);
          if (index < connectionsList.length) {
            connectionsList.removeAt(index);
            _yamlData['connections'] = connectionsList;
          }
        }
      });

      // Show success message via status bar
      widget.onStatusUpdate('Connection deleted successfully');

      // Save changes to file if filePath is provided
      if (widget.filePath != null) {
        _saveChangesToFile();
      }

      // Refresh content to reflect changes
      _refreshContentFromFile();
    }
  }

  void _deleteKernelCmdline(dynamic data, int index) {
    if (widget.filePath != null) {
      // Use yaml_edit to properly remove the kernel cmdline parameter from YAML structure
      try {
        // Read the existing file content
        final file = File(widget.filePath!);
        final content = file.readAsStringSync();

        // Parse the existing YAML
        final yaml = loadYaml(content);

        // Create a YamlEditor instance to properly handle the YAML structure
        final yamlEditor = YamlEditor(content);

        // Remove the kernel cmdline parameter at the specified index
        if (yaml.containsKey('kernel-cmdline') && yaml['kernel-cmdline'] is YamlMap) {
          final kernelCmdlineMap = yaml['kernel-cmdline'] as YamlMap;

          // Find which section (allow, append, remove) contains the item to delete
          String? sectionToDeleteFrom;
          int? itemIndexInSection;

          // Check allow section
          if (kernelCmdlineMap.containsKey('allow') && kernelCmdlineMap['allow'] is List) {
            final allowList = kernelCmdlineMap['allow'] as List;
            if (index < allowList.length) {
              sectionToDeleteFrom = 'allow';
              itemIndexInSection = index;
            }
          }

          // Check append section
          if (sectionToDeleteFrom == null && 
              kernelCmdlineMap.containsKey('append') && 
              kernelCmdlineMap['append'] is List) {
            final appendList = kernelCmdlineMap['append'] as List;
            if (index < appendList.length) {
              sectionToDeleteFrom = 'append';
              itemIndexInSection = index;
            }
          }

          // Check remove section
          if (sectionToDeleteFrom == null && 
              kernelCmdlineMap.containsKey('remove') && 
              kernelCmdlineMap['remove'] is List) {
            final removeList = kernelCmdlineMap['remove'] as List;
            if (index < removeList.length) {
              sectionToDeleteFrom = 'remove';
              itemIndexInSection = index;
            }
          }

          // If we found the section to delete from, remove the item
          if (sectionToDeleteFrom != null && itemIndexInSection != null) {
            yamlEditor.remove(['kernel-cmdline', sectionToDeleteFrom, itemIndexInSection]);

            // Check if the section is now empty and remove it entirely if so
            final section = yamlEditor.parseAt(['kernel-cmdline', sectionToDeleteFrom]).value;
            if (section is List && section.isEmpty) {
              // Remove the entire section if it's now empty
              yamlEditor.remove(['kernel-cmdline', sectionToDeleteFrom]);
            }

            // Check if kernel-cmdline section is now empty and remove it entirely if so
            final kernelCmdlineSection = yamlEditor.parseAt(['kernel-cmdline']).value;
            if (kernelCmdlineSection is YamlMap) {
              bool allSectionsEmpty = true;
              for (var key in ['allow', 'append', 'remove']) {
                if (kernelCmdlineSection.containsKey(key) && 
                    kernelCmdlineSection[key] is List && 
                    (kernelCmdlineSection[key] as List).isNotEmpty) {
                  allSectionsEmpty = false;
                  break;
                }
              }
              if (allSectionsEmpty) {
                // Remove the entire kernel-cmdline section if all sub-sections are empty
                yamlEditor.remove(['kernel-cmdline']);
              }
            }
          }
        }

        // Write back to file using yaml_editor's toString() method
        final newYamlString = yamlEditor.toString();

        // Write back to file
        file.writeAsStringSync(newYamlString);

        // Show success message via status bar
        widget.onStatusUpdate('Kernel parameter deleted successfully');

        // Refresh content to reflect changes
        _refreshContentFromFile();

      } catch (e) {
        widget.onStatusUpdate('Error deleting kernel parameter: $e');
      }
    } else {
      // Fallback for when no file path is provided
      setState(() {
        if (_yamlData.containsKey('kernel-cmdline') && _yamlData['kernel-cmdline'] is YamlMap) {
          final kernelCmdlineMap = _yamlData['kernel-cmdline'] as YamlMap;
          // Convert to regular map to avoid type casting issues
          final mutableKernelCmdline = <String, dynamic>{};
          for (var key in kernelCmdlineMap.keys) {
            mutableKernelCmdline[key.toString()] = kernelCmdlineMap[key];
          }

          // Check if allow exists and is a list
          if (mutableKernelCmdline.containsKey('allow') && mutableKernelCmdline['allow'] is List) {
            final allowList = List.from(mutableKernelCmdline['allow']);
            if (index < allowList.length) {
              allowList.removeAt(index);
              mutableKernelCmdline['allow'] = allowList;

              // Remove the allow section if it's now empty
              if (allowList.isEmpty) {
                mutableKernelCmdline.remove('allow');
              }

              _yamlData['kernel-cmdline'] = mutableKernelCmdline;
            }
          }
          // Check if append exists and is a list
          else if (mutableKernelCmdline.containsKey('append') && mutableKernelCmdline['append'] is List) {
            final appendList = List.from(mutableKernelCmdline['append']);
            if (index < appendList.length) {
              appendList.removeAt(index);
              mutableKernelCmdline['append'] = appendList;

              // Remove the append section if it's now empty
              if (appendList.isEmpty) {
                mutableKernelCmdline.remove('append');
              }

              _yamlData['kernel-cmdline'] = mutableKernelCmdline;
            }
          }
          // Check if remove exists and is a list
          else if (mutableKernelCmdline.containsKey('remove') && mutableKernelCmdline['remove'] is List) {
            final removeList = List.from(mutableKernelCmdline['remove']);
            if (index < removeList.length) {
              removeList.removeAt(index);
              mutableKernelCmdline['remove'] = removeList;

              // Remove the remove section if it's now empty
              if (removeList.isEmpty) {
                mutableKernelCmdline.remove('remove');
              }

              _yamlData['kernel-cmdline'] = mutableKernelCmdline;
            }
          }
        }
      });

      widget.onStatusUpdate('Kernel parameter deleted');

      // Save changes to file if filePath is provided
      if (widget.filePath != null) {
        _saveChangesToFile();
      }

      // Refresh content to reflect changes - this was missing
      _refreshContentFromFile();
    }
  }

  // Save the current YAML data back to the file with proper formatting
  Future<void> _saveChangesToFile() async {
    if (widget.filePath == null) return;

    try {
      final file = File(widget.filePath!);

      // Clean up empty sections
      _cleanupEmptySections();

      // Convert the _yamlData back to YAML string using the YAML serializer
      final yamlString = YamlSerializer.serialize(_yamlData);

      // Write back to file
      await file.writeAsString(yamlString);
    } catch (e) {
      widget.onStatusUpdate('Error saving changes: $e');
    }
  }

  // Clean up empty sections to remove empty defaults and connections
  void _cleanupEmptySections() {
    // Remove empty defaults section
    if (_yamlData.containsKey('defaults')) {
      final defaults = _yamlData['defaults'];
      if (defaults == null || 
          (defaults is Map && (defaults.isEmpty || defaults.length == 0)) ||
          (defaults is YamlMap && (defaults.isEmpty || defaults.length == 0))) {
        _yamlData.remove('defaults');
      }
    }

    // Remove empty connections section
    if (_yamlData.containsKey('connections')) {
      final connections = _yamlData['connections'];
      if (connections == null || 
          (connections is List && connections.isEmpty) ||
          (connections is YamlMap && connections.isEmpty)) {
        _yamlData.remove('connections');
      }
    }

    // Remove empty kernel-cmdline section
    if (_yamlData.containsKey('kernel-cmdline')) {
      final kernelCmdline = _yamlData['kernel-cmdline'];
      if (kernelCmdline == null || 
          (kernelCmdline is Map && (kernelCmdline.isEmpty || kernelCmdline.length == 0)) ||
          (kernelCmdline is YamlMap && (kernelCmdline.isEmpty || kernelCmdline.length == 0))) {
        _yamlData.remove('kernel-cmdline');
      } else if (kernelCmdline is Map || kernelCmdline is YamlMap) {
        // Check if all sub-sections are empty
        final kernelCmdlineMap = kernelCmdline is YamlMap ? kernelCmdline.cast<String, dynamic>() : kernelCmdline as Map<String, dynamic>;
        bool allEmpty = true;

        // Check if all sections (allow, append, remove) are empty
        for (var key in ['allow', 'append', 'remove']) {
          if (kernelCmdlineMap.containsKey(key) && 
              kernelCmdlineMap[key] is List && 
              (kernelCmdlineMap[key] as List).isNotEmpty) {
            allEmpty = false;
            break;
          }
        }

        // If all sections are empty, remove the entire kernel-cmdline section
        if (allEmpty) {
          _yamlData.remove('kernel-cmdline');
        }
      }
    }
  }

  // Manual YAML serialization function with proper formatting
  String _manualSerializeYaml(Map<String, dynamic> data, {int indent = 0}) {
    final StringBuffer buffer = StringBuffer();
    final indentStr = '  ' * indent;

    // Sort keys to ensure consistent output
    final sortedKeys = data.keys.toList()..sort();

    for (var key in sortedKeys) {
      final value = data[key];

      if (value is Map<String, dynamic>) {
        buffer.write('$indentStr$key:\n');
        buffer.write(_manualSerializeYaml(value, indent: indent + 1));
      } else if (value is List) {
        buffer.write('$indentStr$key:\n');
        for (var item in value) {
          if (item is Map<String, dynamic>) {
            buffer.write('$indentStr  - \n');
            buffer.write(_manualSerializeYaml(item, indent: indent + 2));
          } else {
            buffer.write('$indentStr  - $item\n');
          }
        }
      } else if (value is String && value.contains('\n')) {
        // Handle multiline strings properly
        buffer.write('$indentStr$key: |\n');
        final lines = value.split('\n');
        for (var line in lines) {
          buffer.write('$indentStr    $line\n');
        }
      } else {
        buffer.write('$indentStr$key: $value\n');
      }
    }

    return buffer.toString();
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
        editorWidget = Container(
          padding: const EdgeInsets.all(16),
          child: const Text('Editor for this section is not implemented yet.'),
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
            content: Container(
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
          content: Container(
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
