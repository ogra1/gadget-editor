import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

class SimpleConnectionsEditor extends StatefulWidget {
  final dynamic connections;
  final Function(dynamic) onSave;
  final Function() onCancel;

  const SimpleConnectionsEditor({
    super.key,
    required this.connections,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<SimpleConnectionsEditor> createState() => _SimpleConnectionsEditorState();
}

class _SimpleConnectionsEditorState extends State<SimpleConnectionsEditor> {
  late List<Map<String, dynamic>> connectionsList;
  bool isAddingNew = false;
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
      widget.connections.forEach((key, value) {
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
      for (var item in widget.connections) {
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

  void _addNewConnection() {
    setState(() {
      isAddingNew = true;
      _plugSnapIdController.clear();
      _plugController.clear();
      _slotSnapIdController.clear();
      _slotController.clear();
    });
  }

  void _saveConnection() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        connectionsList.add({
          'name': '${_plugController.text}-${_slotController.text}',
          'plug': _plugController.text,
          'plugSnapId': _plugSnapIdController.text,
          'slot': _slotController.text,
          'slotSnapId': _slotSnapIdController.text,
          'isExisting': false,
        });
        isAddingNew = false;
      });
    }
  }

  void _removeConnection(int index) {
    setState(() {
      connectionsList.removeAt(index);
    });
  }

  void _saveChanges() {
    // Convert back to connections structure
    List<Map<String, dynamic>> updatedConnections = [];
    
    for (var conn in connectionsList) {
      Map<String, dynamic> connectionData = {
        'plug': conn['plugSnapId'] != null && conn['plugSnapId'] != ''
            ? '${conn['plugSnapId']}:${conn['plug']}'
            : conn['plug'],
        'slot': conn['slotSnapId'] != null && conn['slotSnapId'] != ''
            ? '${conn['slotSnapId']}:${conn['slot']}'
            : conn['slot'],
      };
      
      if (conn['plugSnapId'] != null && conn['plugSnapId']!.isNotEmpty) {
        connectionData['plugSnapId'] = conn['plugSnapId'];
      }
      
      if (conn['slotSnapId'] != null && conn['slotSnapId']!.isNotEmpty) {
        connectionData['slotSnapId'] = conn['slotSnapId'];
      }
      
      updatedConnections.add(connectionData);
    }
    
    widget.onSave(updatedConnections);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Removed the caption entirely - only one caption should exist
          const SizedBox(height: 16),
          
          // Connection list
          Expanded(
            child: ListView.builder(
              itemCount: connectionsList.length,
              itemBuilder: (context, index) {
                final connection = connectionsList[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Plug line with snap ID - if we have snap ID, show it; otherwise show plug value directly
                        Row(
                          children: [
                            Container(
                              width: 40, // Fixed width to ensure alignment
                              alignment: Alignment.centerLeft,
                              child: const Text('Plug: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: Text(
                                // Show snapId:interface if snapId exists, otherwise just interface
                                '${connection['plugSnapId'] != null && connection['plugSnapId'] != '' ? '${connection['plugSnapId']!}:' : ''}${connection['plug'] ?? 'N/A'}',
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                        // Slot line - only show if slot is defined, without "(optional)" text
                        if (connection['slot'] != null && connection['slot']!.isNotEmpty)
                          Row(
                            children: [
                              Container(
                                width: 40, // Fixed width to ensure alignment
                                alignment: Alignment.centerLeft,
                                child: const Text('Slot: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Expanded(
                                child: Text(
                                  // Show snapId:interface if snapId exists, otherwise just interface
                                  '${connection['slotSnapId'] != null && connection['slotSnapId'] != '' ? '${connection['slotSnapId']!}:' : ''}${connection['slot'] ?? 'N/A'}',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _removeConnection(index),
                              tooltip: 'Delete Connection',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Add new connection button
          if (!isAddingNew)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addNewConnection,
              tooltip: 'Add New Connection',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          
          if (isAddingNew) ...[
            const SizedBox(height: 16),
            // Input block constrained to 2/3 width but wrapped in a container that spans 100%
            Row(
              children: [
                Expanded(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 2 / 3,
                    child: Form(
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
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter a plug snap ID';
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
                              // Reduced spacer size from 30% to 5% to give more space to fields
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.05,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
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
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3, // Reduced flex to give less space to interface
                                      child: TextFormField(
                                        controller: _slotController,
                                        decoration: const InputDecoration(labelText: 'Interface Slot'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Reduced spacer size from 30% to 5% to give more space to fields
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.05,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Buttons row - this will stay in bottom right
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    isAddingNew = false;
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: _saveConnection,
                                child: const Text('Save Connection'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Save and Cancel buttons (only shown when not adding new)
          if (!isAddingNew)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _saveChanges,
                  child: const Text('Save Changes'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
