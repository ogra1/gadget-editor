import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

class SimpleVolumeEditor extends StatefulWidget {
  final dynamic volumes;
  final Function(dynamic) onSave;
  final Function() onCancel;

  const SimpleVolumeEditor({
    super.key,
    required this.volumes,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<SimpleVolumeEditor> createState() => _SimpleVolumeEditorState();
}

class _SimpleVolumeEditorState extends State<SimpleVolumeEditor> {
  late List<Map<String, dynamic>> partitions;
  late List<Map<String, dynamic>> volumesList;
  bool isAddingNew = false;
  final _formKey = GlobalKey<FormState>();

  // Form fields
  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();
  final _roleController = TextEditingController();
  final _typeController = TextEditingController();
  final _filesystemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseVolumes();
  }

  void _parseVolumes() {
    volumesList = [];
    partitions = [];

    if (widget.volumes is YamlMap) {
      widget.volumes.forEach((volumeName, volumeData) {
        volumesList.add({
          'name': volumeName,
          'data': volumeData,
        });

        if (volumeData['structure'] is List) {
          for (var item in volumeData['structure']) {
            partitions.add({
              'volume': volumeName,
              'name': item['name'],
              'size': item['size'],
              'role': item['role'],
              'type': item['type'],
              'filesystem': item['filesystem'],
              'isExisting': true,
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    _roleController.dispose();
    _typeController.dispose();
    _filesystemController.dispose();
    super.dispose();
  }

  void _addNewPartition() {
    setState(() {
      isAddingNew = true;
      _nameController.clear();
      _sizeController.clear();
      _roleController.clear();
      _typeController.clear();
      _filesystemController.clear();
    });
  }

  void _savePartition() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        partitions.add({
          'name': _nameController.text,
          'size': _sizeController.text,
          'role': _roleController.text,
          'type': _typeController.text,
          'filesystem': _filesystemController.text,
          'isExisting': false,
        });
        isAddingNew = false;
      });
    }
  }

  void _removePartition(int index) {
    setState(() {
      partitions.removeAt(index);
    });
  }

  void _saveChanges() {
    // Convert back to volumes structure
    Map<String, dynamic> updatedVolumes = {};

    for (var partition in partitions) {
      final volumeName = partition['volume'];
      if (!updatedVolumes.containsKey(volumeName)) {
        updatedVolumes[volumeName] = {
          'structure': [],
        };
      }

      updatedVolumes[volumeName]['structure'].add({
        'name': partition['name'],
        'size': partition['size'],
        'role': partition['role'],
        'type': partition['type'],
        'filesystem': partition['filesystem'],
      });
    }

    widget.onSave(updatedVolumes);
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

          // Partition list
          Expanded(
            child: ListView.builder(
              itemCount: partitions.length,
              itemBuilder: (context, index) {
                final partition = partitions[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Partition: ${partition['name'] ?? 'Unnamed'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('Size: ${partition['size'] ?? 'N/A'}'),
                        Text('Role: ${partition['role'] ?? 'N/A'}'),
                        Text('Type: ${partition['type'] ?? 'N/A'}'),
                        Text('Filesystem: ${partition['filesystem'] ?? 'N/A'}'),
                        if (partition['isExisting'] == true)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _removePartition(index),
                                child: const Text('Remove'),
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

          // Add new partition button
          if (!isAddingNew)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addNewPartition,
              tooltip: 'Add New Partition',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),

          if (isAddingNew) ...[
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Partition Name'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _sizeController,
                    decoration: const InputDecoration(labelText: 'Size (e.g., 100M, 1G)'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a size';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _roleController,
                    decoration: const InputDecoration(labelText: 'Role'),
                  ),
                  TextFormField(
                    controller: _typeController,
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  TextFormField(
                    controller: _filesystemController,
                    decoration: const InputDecoration(labelText: 'Filesystem'),
                  ),
                  const SizedBox(height: 16),
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
                        onPressed: _savePartition,
                        child: const Text('Save Partition'),
                      ),
                    ],
                  ),
                ],
              ),
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
