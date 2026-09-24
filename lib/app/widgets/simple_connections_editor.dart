import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml_edit/yaml_edit.dart';

class SimpleConnectionsEditor extends StatefulWidget {
  final dynamic connections;
  final String? filePath;
  final Function(dynamic) onSave;
  final Function() onCancel;
  final Function(String) onStatusUpdate;

  const SimpleConnectionsEditor({
    super.key,
    required this.connections,
    this.filePath,
    required this.onSave,
    required this.onCancel,
    required this.onStatusUpdate,
  });

  @override
  State<SimpleConnectionsEditor> createState() => _SimpleConnectionsEditorState();
}

class _SimpleConnectionsEditorState extends State<SimpleConnectionsEditor> {
  late List<Map<String, dynamic>> connectionsList;
  final _formKey = GlobalKey<FormState>();
  
  // Form fields
  final _plugSnapIdController = TextEditingController();
  final _plugController = TextEditingController();
  final _slotSnapIdController = TextEditingController();
  final _slotController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseConnections();
  }

  void _parseConnections() {
    connectionsList = [];
    
    if (widget.connections is YamlMap) {
      // Convert YamlMap to Map<String, dynamic> properly
      final yamlMap = widget.connections.cast<String, dynamic>();
      
      yamlMap.forEach((key, value) {
        if (value is YamlMap) {
          connectionsList.add({
            'name': key,
            'plug': value['plug'],
            'plugSnapId': value['plugSnapId'],
            'slot': value['slot'],
            'slotSnapId': value['slotSnapId'],
            'isExisting': true,
          });
        } else if (value is List) {
          for (var item in value) {
            if (item is YamlMap) {
              // Parse the combined format for plug and slot
              String? plug = item['plug'];
              String? slot = item['slot'];
              
              String? plugSnapId;
              String? plugInterface;
              
              if (plug != null && plug.contains(':')) {
                final parts = plug.split(':');
                if (parts.length >= 2) {
                  plugSnapId = parts[0];
                  plugInterface = parts.sublist(1).join(':');
                }
              }
              
              String? slotSnapId;
              String? slotInterface;
              
              if (slot != null && slot.contains(':')) {
                final parts = slot.split(':');
                if (parts.length >= 2) {
                  slotSnapId = parts[0];
                  slotInterface = parts.sublist(1).join(':');
                }
              }
              
              connectionsList.add({
                'name': item['name'] ?? '${plug ?? ''}-${slot ?? ''}',
                'plug': plugInterface ?? plug,
                'plugSnapId': plugSnapId,
                'slot': slotInterface ?? slot,
                'slotSnapId': slotSnapId,
                'isExisting': true,
              });
            }
          }
        }
      });
    } else if (widget.connections is List) {
      // Create a mutable copy of the List
      final mutableList = List.from(widget.connections);
      
      for (var item in mutableList) {
        if (item is YamlMap) {
          // Parse the combined format for plug and slot
          String? plug = item['plug'];
          String? slot = item['slot'];
          
          String? plugSnapId;
          String? plugInterface;
          
          if (plug != null && plug.contains(':')) {
            final parts = plug.split(':');
            if (parts.length >= 2) {
              plugSnapId = parts[0];
              plugInterface = parts.sublist(1).join(':');
            }
          }
          
          String? slotSnapId;
          String? slotInterface;
          
          if (slot != null && slot.contains(':')) {
            final parts = slot.split(':');
            if (parts.length >= 2) {
              slotSnapId = parts[0];
              slotInterface = parts.sublist(1).join(':');
            }
          }
          
          connectionsList.add({
            'name': item['name'] ?? '${plug ?? ''}-${slot ?? ''}',
            'plug': plugInterface ?? plug,
            'plugSnapId': plugSnapId,
            'slot': slotInterface ?? slot,
            'slotSnapId': slotSnapId,
            'isExisting': true,
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _plugSnapIdController.dispose();
    _plugController.dispose();
    _slotSnapIdController.dispose();
    _slotController.dispose();
    super.dispose();
  }

  // Validate snap ID format
  bool _isValidSnapId(String? snapId) {
    if (snapId == null || snapId.isEmpty) {
      return true; // Empty is allowed for optional fields
    }
    
    // Snap IDs are exactly 32 characters
    return snapId.length == 32;
  }

  // Validate that both snap ID and interface are provided together for plug
  bool _validatePlugConnection(String? snapId, String? interface) {
    // If snap ID is provided, interface must also be provided
    if (snapId != null && snapId.isNotEmpty) {
      return interface != null && interface.isNotEmpty;
    }
    // If no snap ID, interface is optional (but if provided, must have snap ID)
    if (interface != null && interface.isNotEmpty) {
      return false; // Interface without snap ID is invalid
    }
    return true; // Both empty is valid
  }

  // Validate that both snap ID and interface are provided together for slot
  bool _validateSlotConnection(String? snapId, String? interface) {
    // If snap ID is provided, interface must also be provided
    if (snapId != null && snapId.isNotEmpty) {
      return interface != null && interface.isNotEmpty;
    }
    // If no snap ID, interface is optional (but if provided, must have snap ID)
    if (interface != null && interface.isNotEmpty) {
      return false; // Interface without snap ID is invalid
    }
    return true; // Both empty is valid
  }

  // Save the updated connections back to the file
  Future<void> _saveChangesToYaml() async {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

    try {
      // Get form values
      final plugSnapId = _plugSnapIdController.text.trim();
      final plug = _plugController.text.trim();
      final slotSnapId = _slotSnapIdController.text.trim();
      final slot = _slotController.text.trim();
      
      // Validate inputs
      if (plug.isEmpty) {
        widget.onStatusUpdate('Error: Please enter a plug');
        return;
      }
      
      // Validate snap ID formats
      if (plugSnapId.isNotEmpty && !_isValidSnapId(plugSnapId)) {
        widget.onStatusUpdate('Error: Invalid plug snap ID format. Must be 32 characters');
        return;
      }
      
      if (slotSnapId.isNotEmpty && !_isValidSnapId(slotSnapId)) {
        widget.onStatusUpdate('Error: Invalid slot snap ID format. Must be 32 characters');
        return;
      }
      
      // Validate that if snap IDs are provided, interfaces are also provided
      if (!_validatePlugConnection(plugSnapId, plug)) {
        widget.onStatusUpdate('Error: Plug requires snap ID and interface name');
        return;
      }
      
      if (!_validateSlotConnection(slotSnapId, slot)) {
        widget.onStatusUpdate('Error: Slot requires snap ID and interface name');
        return;
      }
      
      // Read the existing file content
      final file = File(widget.filePath!);
      final content = await file.readAsString();
      
      // Parse the existing YAML
      final yaml = loadYaml(content);
      
      // Create a YamlEditor instance to properly handle the YAML structure
      final yamlEditor = YamlEditor(content);
      
      // Create the new connection
      Map<String, dynamic> newConnection = {};
      
      // Build plug string
      if (plugSnapId.isNotEmpty) {
        newConnection['plug'] = '$plugSnapId:$plug';
      } else {
        newConnection['plug'] = plug;
      }
      
      // Build slot string if provided
      if (slot.isNotEmpty) {
        if (slotSnapId.isNotEmpty) {
          newConnection['slot'] = '$slotSnapId:$slot';
        } else {
          newConnection['slot'] = slot;
        }
      }
      
      // Handle connections structure - THIS IS THE CORRECT APPROACH
      if (yaml.containsKey('connections')) {
        // Connections already exists - update it properly
        final existingConnections = yaml['connections'];
        List<dynamic> updatedConnections;
        
        if (existingConnections is List) {
          updatedConnections = List.from(existingConnections);
        } else if (existingConnections is YamlMap) {
          final connectionsList = <dynamic>[];
          for (var key in existingConnections.keys) {
            connectionsList.add(existingConnections[key]);
          }
          updatedConnections = connectionsList;
        } else {
          updatedConnections = [newConnection];
        }
        
        // Add new connection to the list - avoiding duplicates
        bool connectionExists = false;
        for (var existing in updatedConnections) {
          if (existing == newConnection) {
            connectionExists = true;
            break;
          }
        }
        
        if (!connectionExists) {
          updatedConnections.add(newConnection);
        }
        
        // Update connections directly
        yamlEditor.update(['connections'], updatedConnections);
      } else {
        // NEW connections section - USE THE EXACT APPROACH FROM OTHER AI
        // The key is to parse the root structure and rebuild it
        final rootMap = yamlEditor.parseAt([]) as YamlMap;
        final updatedRoot = Map.from(rootMap);
        
        // Add the new connections section to the updated root
        updatedRoot['connections'] = [newConnection];
        
        // Use wrapAsYamlNode but with careful formatting to avoid quotes
        // The approach from the other AI example - rebuild the entire structure
        yamlEditor.update([], wrapAsYamlNode(updatedRoot, collectionStyle: CollectionStyle.BLOCK));
      }
      
      // Write back to file using yaml_editor's toString() method
      final newYamlString = yamlEditor.toString();
      
      // Write back to file
      await file.writeAsString(newYamlString);
      
      // Show success message via status bar
      widget.onStatusUpdate('Connection added successfully');
      
      // Notify parent that changes were saved
      widget.onSave([newConnection]);
      
      // Clear form fields
      _plugSnapIdController.clear();
      _plugController.clear();
      _slotSnapIdController.clear();
      _slotController.clear();
      
    } catch (e) {
      widget.onStatusUpdate('Error saving changes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input block for new connection - always shown
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plug line with label
              Row(
                children: [
                  const SizedBox(width: 100, child: Text('Plug:')),
                  const SizedBox(width: 16), // Added padding between label and field
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5, // Increased flex to give more space to snap ID
                          child: TextFormField(
                            controller: _plugSnapIdController,
                            decoration: const InputDecoration(labelText: 'Snap ID'),
                            validator: (value) {
                              if (value != null && value.isNotEmpty && !_isValidSnapId(value)) {
                                return 'Invalid snap ID format. Must be 32 characters';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3, // Reduced flex to give less space to interface
                          child: TextFormField(
                            controller: _plugController,
                            decoration: const InputDecoration(labelText: 'Interface Plug'),
                            validator: (value) {
                              // Validate that if snap ID is provided, interface is also provided
                              final plugSnapId = _plugSnapIdController.text.trim();
                              if (plugSnapId.isNotEmpty && (value == null || value.isEmpty)) {
                                return 'Plug requires snap ID and interface name';
                              }
                              if (value == null || value.isEmpty) {
                                return 'Please enter a plug';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Slot line with label - keeping "(optional)" in input form
              Row(
                children: [
                  const SizedBox(width: 100, child: Text('Slot (optional):')),
                  const SizedBox(width: 16), // Added padding between label and field
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5, // Increased flex to give more space to snap ID
                          child: TextFormField(
                            controller: _slotSnapIdController,
                            decoration: const InputDecoration(labelText: 'Snap ID'),
                            validator: (value) {
                              if (value != null && value.isNotEmpty && !_isValidSnapId(value)) {
                                return 'Invalid snap ID format. Must be 32 characters';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3, // Reduced flex to give less space to interface
                          child: TextFormField(
                            controller: _slotController,
                            decoration: const InputDecoration(labelText: 'Interface Slot'),
                            validator: (value) {
                              // Validate that if snap ID is provided, interface is also provided
                              final slotSnapId = _slotSnapIdController.text.trim();
                              if (slotSnapId.isNotEmpty && (value == null || value.isEmpty)) {
                                return 'Slot requires snap ID and interface name';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
