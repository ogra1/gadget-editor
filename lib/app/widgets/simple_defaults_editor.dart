import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import 'package:yaml_edit/yaml_edit.dart';

class SimpleDefaultsEditor extends StatefulWidget {
  final dynamic defaults;
  final String? filePath;
  final Function(dynamic) onSave;
  final Function() onCancel;
  final Function(String) onStatusUpdate;

  const SimpleDefaultsEditor({
    super.key,
    required this.defaults,
    this.filePath,
    required this.onSave,
    required this.onCancel,
    required this.onStatusUpdate,
  });

  @override
  State<SimpleDefaultsEditor> createState() => _SimpleDefaultsEditorState();
}

class _SimpleDefaultsEditorState extends State<SimpleDefaultsEditor> {
  late List<Map<String, dynamic>> defaultsList;
  final _formKey = GlobalKey<FormState>();
  
  // Form fields
  final _snapIdController = TextEditingController();
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  bool _isMultilineExpanded = false;
  final _multilineController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseDefaults();
  }

  void _parseDefaults() {
    defaultsList = [];
    
    // Handle the case where defaults is a YamlMap
    if (widget.defaults is YamlMap) {
      final yamlMap = widget.defaults;
      if (yamlMap is YamlMap) {
        // Properly convert YamlMap to Map<String, dynamic>
        final map = <String, dynamic>{};
        for (var key in yamlMap.keys) {
          // Convert key to string to avoid type casting issues
          final keyStr = key.toString();
          map[keyStr] = yamlMap[key];
        }
        // Now iterate through the converted map
        map.forEach((key, value) {
          defaultsList.add({
            'key': key,
            'value': value,
            'isExisting': true,
          });
        });
      }
    } else if (widget.defaults is Map) {
      (widget.defaults as Map<String, dynamic>).forEach((key, value) {
        defaultsList.add({
          'key': key,
          'value': value,
          'isExisting': true,
        });
      });
    }
  }

  @override
  void dispose() {
    _snapIdController.dispose();
    _keyController.dispose();
    _valueController.dispose();
    _multilineController.dispose();
    super.dispose();
  }

  // Validate snap ID format - can be 32 chars or "system"
  bool _isValidSnapId(String? snapId) {
    if (snapId == null || snapId.isEmpty) {
      return true; // Empty is allowed for optional fields
    }
    
    // Snap IDs are either exactly 32 characters or "system"
    return (snapId.length == 32) || (snapId == 'system');
  }

  // Save the updated defaults back to the file
  Future<void> _saveChangesToYaml() async {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

    try {
      // Get the snap ID and key from the form
      final snapId = _snapIdController.text.trim();
      final key = _keyController.text.trim();
      
      // Get the value - use multiline controller if expanded, otherwise regular controller
      final value = _isMultilineExpanded 
          ? _multilineController.text.trim() 
          : _valueController.text.trim();
      
      // Validate inputs - all fields are required
      if (snapId.isEmpty) {
        widget.onStatusUpdate('Error: Please enter a snap ID');
        return;
      }
      
      if (key.isEmpty) {
        widget.onStatusUpdate('Error: Please enter a key');
        return;
      }
      
      if (value.isEmpty) {
        widget.onStatusUpdate('Error: Please enter a value');
        return;
      }
      
      // Validate snap ID format
      if (!_isValidSnapId(snapId)) {
        widget.onStatusUpdate('Error: Invalid snap ID format. Must be 32 characters or "system"');
        return;
      }
      
      // Read the existing file content
      final file = File(widget.filePath!);
      final content = await file.readAsString();
      
      // Parse the existing YAML
      final yaml = loadYaml(content);
      
      // Create a YamlEditor instance to properly handle the YAML structure
      final yamlEditor = YamlEditor(content);
      
      // Handle nested structure in defaults - THIS IS THE CORRECT APPROACH
      Map<String, dynamic> updatedDefaults = {};
      
      // If defaults already exists, copy it
      if (yaml.containsKey('defaults') && yaml['defaults'] is Map) {
        final existingDefaults = yaml['defaults'] as Map;
        updatedDefaults = Map.from(existingDefaults);
      } else if (yaml.containsKey('defaults') && yaml['defaults'] is YamlMap) {
        final existingDefaults = yaml['defaults'] as YamlMap;
        // Convert YamlMap to Map<String, dynamic> properly
        final map = <String, dynamic>{};
        for (var key in existingDefaults.keys) {
          map[key.toString()] = existingDefaults[key];
        }
        updatedDefaults = map;
      }
      
      // Create the proper nested structure for snap ID -> key path -> value
      Map<String, dynamic> snapDefaults = updatedDefaults;
      
      // Create snap ID entry if it doesn't exist
      if (!snapDefaults.containsKey(snapId)) {
        snapDefaults[snapId] = {};
      }
      
      // Ensure we're working with a proper Map<String, dynamic> for the snap level
      dynamic snapLevel = snapDefaults[snapId];
      Map<String, dynamic> currentLevel;
      
      // Handle conversion from YamlMap to Map<String, dynamic> if needed
      if (snapLevel is YamlMap) {
        final map = <String, dynamic>{};
        for (var key in snapLevel.keys) {
          map[key.toString()] = snapLevel[key];
        }
        snapDefaults[snapId] = map;
        currentLevel = map;
      } else if (snapLevel is Map<String, dynamic>) {
        currentLevel = snapLevel;
      } else {
        // If it's not a map, create a new one
        snapDefaults[snapId] = <String, dynamic>{};
        currentLevel = snapDefaults[snapId] as Map<String, dynamic>;
      }
      
      // Parse the key to handle nested structure (e.g., "foo.bar.baz")
      final keyParts = key.split('.');
      
      // Navigate to the parent level of the key
      for (int i = 0; i < keyParts.length - 1; i++) {
        final part = keyParts[i];
        if (!currentLevel.containsKey(part)) {
          // Create a new map with explicit String keys
          final newMap = <String, dynamic>{};
          currentLevel[part] = newMap;
          currentLevel = newMap;
        } else {
          // Ensure we're working with a Map<String, dynamic>
          final levelValue = currentLevel[part];
          if (levelValue is Map<String, dynamic>) {
            currentLevel = levelValue;
          } else if (levelValue is YamlMap) {
            // Handle YamlMap case by converting to regular Map
            final yamlMap = levelValue;
            final map = <String, dynamic>{};
            for (var key in yamlMap.keys) {
              map[key.toString()] = yamlMap[key];
            }
            currentLevel[part] = map;
            currentLevel = map;
          } else {
            // If it's not a map, replace it with an empty map
            final newMap = <String, dynamic>{};
            currentLevel[part] = newMap;
            currentLevel = newMap;
          }
        }
      }
      
      // Set the final value - ensure proper formatting without quotes
      final lastKey = keyParts.last;
      
      // Handle multiline values properly by using wrapAsYamlNode
      dynamic yamlValue;
      if (_isMultilineExpanded && value.isNotEmpty) {
        // For multiline values, we need to wrap them properly
        yamlValue = wrapAsYamlNode(value, scalarStyle: ScalarStyle.LITERAL);
      } else {
        // For regular values, convert to appropriate type to avoid quotes
        if (value == 'true') {
          yamlValue = true;
        } else if (value == 'false') {
          yamlValue = false;
        } else if (value == 'null') {
          yamlValue = null;
        } else if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
          // Try to parse as number
          try {
            if (value.contains('.')) {
              yamlValue = double.parse(value);
            } else {
              yamlValue = int.parse(value);
            }
          } catch (e) {
            yamlValue = value;
          }
        } else {
          yamlValue = value;
        }
      }
      
      currentLevel[lastKey] = yamlValue;
      
      // Handle the case where defaults section already exists vs needs to be created
      if (yaml.containsKey('defaults')) {
        // Update existing defaults section
        yamlEditor.update(['defaults'], updatedDefaults);
      } else {
        // Create new defaults section at the root level
        final rootMap = yamlEditor.parseAt([]) as YamlMap;
        final updatedRoot = Map.from(rootMap);
        updatedRoot['defaults'] = updatedDefaults;
        
        // Use wrapAsYamlNode with proper formatting to avoid quotes
        final wrappedRoot = wrapAsYamlNode(updatedRoot, collectionStyle: CollectionStyle.BLOCK);
        yamlEditor.update([], wrappedRoot);
      }
      
      // Write back to file using yaml_editor's toString() method
      final newYamlString = yamlEditor.toString();
      
      // Write back to file
      await file.writeAsString(newYamlString);
      
      // Show success message via status bar
      widget.onStatusUpdate('Default added successfully');
      
      // Notify parent that changes were saved
      // We pass the updated defaults to trigger a refresh
      widget.onSave(updatedDefaults);
      
      // Clear form fields
      _snapIdController.clear();
      _keyController.clear();
      _valueController.clear();
      _multilineController.clear();
      setState(() {
        _isMultilineExpanded = false;
      });
      
    } catch (e) {
      widget.onStatusUpdate('Error saving changes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input block for new default - always shown
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Snap ID field with caption
              Row(
                children: [
                  const SizedBox(width: 100, child: Text('Snap:')),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _snapIdController,
                      decoration: const InputDecoration(labelText: 'Snap ID'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a snap ID';
                        }
                        if (!_isValidSnapId(value)) {
                          return 'Invalid snap ID format. Must be 32 characters or "system"';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Key and Value fields in the same row
              Row(
                children: [
                  // 70% for Key
                  Expanded(
                    flex: 7,
                    child: Row(
                      children: [
                        const SizedBox(width: 100, child: Text('Option:')),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _keyController,
                            decoration: const InputDecoration(labelText: 'Key (e.g., foo.bar.baz)'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a key';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 30% for Value field with multiline toggle
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _valueController,
                            decoration: const InputDecoration(labelText: 'Value'),
                            validator: (value) {
                              // Only validate when multiline is not expanded
                              if (!_isMultilineExpanded && (value == null || value.isEmpty)) {
                                return 'Please enter a value';
                              }
                              return null;
                            },
                            enabled: !_isMultilineExpanded,
                          ),
                        ),
                        // Multiline toggle icon
                        IconButton(
                          icon: Icon(
                            _isMultilineExpanded ? Icons.description : Icons.description_outlined,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _isMultilineExpanded = !_isMultilineExpanded;
                              if (_isMultilineExpanded) {
                                // When expanding, copy current value to multiline controller
                                _multilineController.text = _valueController.text;
                              } else {
                                // When collapsing, copy back to regular controller
                                _valueController.text = _multilineController.text;
                              }
                            });
                          },
                          tooltip: 'Add MultiLine text',
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Multiline text area (spans underneath both key and value fields with proper alignment)
              if (_isMultilineExpanded)
                Container(
                  margin: const EdgeInsets.only(top: 8, left: 116), // Adjusted to align with caption fields
                  height: 150, // Fixed height for multiline area
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: TextFormField(
                      controller: _multilineController,
                      decoration: const InputDecoration(
                        hintText: 'Paste multiline text here...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(8),
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      expands: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a value';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              
              const SizedBox(height: 8),
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
