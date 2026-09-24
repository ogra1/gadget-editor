import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import 'package:yaml_edit/yaml_edit.dart';

class SimpleKernelCmdlineEditor extends StatefulWidget {
  final dynamic kernelCmdline;
  final String? filePath;
  final Function(dynamic) onSave;
  final Function() onCancel;
  final Function(String) onStatusUpdate;

  const SimpleKernelCmdlineEditor({
    super.key,
    required this.kernelCmdline,
    this.filePath,
    required this.onSave,
    required this.onCancel,
    required this.onStatusUpdate,
  });

  @override
  State<SimpleKernelCmdlineEditor> createState() => _SimpleKernelCmdlineEditorState();
}

class _SimpleKernelCmdlineEditorState extends State<SimpleKernelCmdlineEditor> {
  late List<Map<String, dynamic>> allowList;
  late List<Map<String, dynamic>> appendList;
  late List<Map<String, dynamic>> removeList;
  final _formKey = GlobalKey<FormState>();
  
  // Form fields
  final _parameterController = TextEditingController();
  final _valueController = TextEditingController();
  final _typeController = TextEditingController();
  bool _isAddingAllow = false;
  String _selectedType = 'allow'; // Default to allow

  @override
  void initState() {
    super.initState();
    _parseKernelCmdline();
  }

  void _parseKernelCmdline() {
    allowList = [];
    appendList = [];
    removeList = [];
    
    if (widget.kernelCmdline is YamlMap) {
      final yamlMap = widget.kernelCmdline;
      
      // Parse allow list
      if (yamlMap.containsKey('allow') && yamlMap['allow'] is List) {
        final allowListData = yamlMap['allow'] as List;
        for (var item in allowListData) {
          if (item is String) {
            // Parse parameter=value format
            final parts = item.split('=');
            if (parts.length == 2) {
              allowList.add({
                'parameter': parts[0],
                'value': parts[1],
                'isExisting': true,
              });
            } else {
              // Handle parameters without values
              allowList.add({
                'parameter': item,
                'value': '',
                'isExisting': true,
              });
            }
          }
        }
      }
      
      // Parse append list
      if (yamlMap.containsKey('append') && yamlMap['append'] is List) {
        final appendListData = yamlMap['append'] as List;
        for (var item in appendListData) {
          if (item is String) {
            // Parse parameter=value format
            final parts = item.split('=');
            if (parts.length == 2) {
              appendList.add({
                'parameter': parts[0],
                'value': parts[1],
                'isExisting': true,
              });
            } else {
              // Handle parameters without values
              appendList.add({
                'parameter': item,
                'value': '',
                'isExisting': true,
              });
            }
          }
        }
      }
      
      // Parse remove list
      if (yamlMap.containsKey('remove') && yamlMap['remove'] is List) {
        final removeListData = yamlMap['remove'] as List;
        for (var item in removeListData) {
          if (item is String) {
            // Parse parameter=value format
            final parts = item.split('=');
            if (parts.length == 2) {
              removeList.add({
                'parameter': parts[0],
                'value': parts[1],
                'isExisting': true,
              });
            } else {
              // Handle parameters without values
              removeList.add({
                'parameter': item,
                'value': '',
                'isExisting': true,
              });
            }
          }
        }
      }
    } else if (widget.kernelCmdline is Map) {
      final map = widget.kernelCmdline as Map<String, dynamic>;
      
      // Parse allow list
      if (map.containsKey('allow') && map['allow'] is List) {
        final allowListData = map['allow'] as List;
        for (var item in allowListData) {
          if (item is String) {
            // Parse parameter=value format
            final parts = item.split('=');
            if (parts.length == 2) {
              allowList.add({
                'parameter': parts[0],
                'value': parts[1],
                'isExisting': true,
              });
            } else {
              // Handle parameters without values
              allowList.add({
                'parameter': item,
                'value': '',
                'isExisting': true,
              });
            }
          }
        }
      }
      
      // Parse append list
      if (map.containsKey('append') && map['append'] is List) {
        final appendListData = map['append'] as List;
        for (var item in appendListData) {
          if (item is String) {
            // Parse parameter=value format
            final parts = item.split('=');
            if (parts.length == 2) {
              appendList.add({
                'parameter': parts[0],
                'value': parts[1],
                'isExisting': true,
              });
            } else {
              // Handle parameters without values
              appendList.add({
                'parameter': item,
                'value': '',
                'isExisting': true,
              });
            }
          }
        }
      }
      
      // Parse remove list
      if (map.containsKey('remove') && map['remove'] is List) {
        final removeListData = map['remove'] as List;
        for (var item in removeListData) {
          if (item is String) {
            // Parse parameter=value format
            final parts = item.split('=');
            if (parts.length == 2) {
              removeList.add({
                'parameter': parts[0],
                'value': parts[1],
                'isExisting': true,
              });
            } else {
              // Handle parameters without values
              removeList.add({
                'parameter': item,
                'value': '',
                'isExisting': true,
              });
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _parameterController.dispose();
    _valueController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  // Save the updated kernel cmdline back to the file
  Future<void> _saveChangesToYaml() async {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

    try {
      // Get form values
      final parameter = _parameterController.text.trim();
      final value = _valueController.text.trim();
      final type = _selectedType;
      
      // Validate inputs
      if (parameter.isEmpty) {
        widget.onStatusUpdate('Error: Please enter a parameter');
        return;
      }
      
      // Read the existing file content
      final file = File(widget.filePath!);
      final content = await file.readAsString();
      
      // Parse the existing YAML
      final yaml = loadYaml(content);
      
      // Create a YamlEditor instance
      final yamlEditor = YamlEditor(content);
      
      // Handle kernel-cmdline structure - use the same approach as connections editor
      Map<String, dynamic> updatedKernelCmdline = {};
      
      // If kernel-cmdline already exists, copy it
      if (yaml.containsKey('kernel-cmdline') && yaml['kernel-cmdline'] is YamlMap) {
        final existingKernelCmdline = yaml['kernel-cmdline'] as YamlMap;
        // Convert YamlMap to Map<String, dynamic> properly
        for (var key in existingKernelCmdline.keys) {
          updatedKernelCmdline[key.toString()] = existingKernelCmdline[key];
        }
      } else if (yaml.containsKey('kernel-cmdline') && yaml['kernel-cmdline'] is Map) {
        // Handle Map case
        final existingKernelCmdline = yaml['kernel-cmdline'] as Map;
        updatedKernelCmdline = Map.from(existingKernelCmdline);
      }
      
      // Handle the selected type list - append to the end instead of prepending
      List<String> updatedList = [];
      
      // If the selected type list already exists, copy it
      if (updatedKernelCmdline.containsKey(type) && updatedKernelCmdline[type] is List) {
        final existingList = updatedKernelCmdline[type] as List;
        updatedList = List.from(existingList);
      }
      
      // Create the new parameter entry
      String newEntry;
      if (value.isNotEmpty) {
        newEntry = '$parameter=$value';
      } else {
        newEntry = parameter;
      }
      
      // Add to the selected type list - append to the end instead of prepending
      updatedList.add(newEntry);
      
      // Update the selected type list in kernel-cmdline
      updatedKernelCmdline[type] = updatedList;
      
      // Handle the case where defaults section already exists vs needs to be created
      if (yaml.containsKey('kernel-cmdline')) {
        // Update existing defaults section
        yamlEditor.update(['kernel-cmdline'], updatedKernelCmdline);
      } else {
        // Create new defaults section at the root level
        final rootMap = yamlEditor.parseAt([]) as YamlMap;
        final updatedRoot = Map.from(rootMap);
        updatedRoot['kernel-cmdline'] = updatedKernelCmdline;
        
        // Use wrapAsYamlNode with proper formatting to avoid quotes
        final wrappedRoot = wrapAsYamlNode(updatedRoot, collectionStyle: CollectionStyle.BLOCK);
        yamlEditor.update([], wrappedRoot);
      }
      
      // Write back to file using yaml_editor's toString() method
      final newYamlString = yamlEditor.toString();
      
      // Write back to file
      await file.writeAsString(newYamlString);
      
      // Show success message via status bar
      widget.onStatusUpdate('Kernel parameter added successfully');
      
      // Notify parent that changes were saved
      widget.onSave(updatedKernelCmdline);
      
      // Clear form fields
      _parameterController.clear();
      _valueController.clear();
      
    } catch (e) {
      widget.onStatusUpdate('Error saving changes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input block for new kernel parameter - always shown
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type selection dropdown at the top
              Row(
                children: [
                  const SizedBox(width: 100, child: Text('Type:')),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedType,
                      items: const [
                        DropdownMenuItem(value: 'allow', child: Text('Allow')),
                        DropdownMenuItem(value: 'append', child: Text('Append')),
                        DropdownMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedType = newValue ?? 'allow';
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Parameter type',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Parameter and value fields in the same row
              Row(
                children: [
                  const SizedBox(width: 100, child: Text('Parameter:')),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _parameterController,
                      decoration: const InputDecoration(labelText: 'Kernel parameter name'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a parameter';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _valueController,
                      decoration: const InputDecoration(
                        labelText: 'Value (optional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _saveChangesToYaml,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
