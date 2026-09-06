import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

class SimpleDefaultsEditor extends StatefulWidget {
  final dynamic defaults;
  final Function(dynamic) onSave;
  final Function() onCancel;

  const SimpleDefaultsEditor({
    super.key,
    required this.defaults,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<SimpleDefaultsEditor> createState() => _SimpleDefaultsEditorState();
}

class _SimpleDefaultsEditorState extends State<SimpleDefaultsEditor> {
  late List<Map<String, dynamic>> defaultsList;
  bool isAddingNew = false;
  final _formKey = GlobalKey<FormState>();
  
  // Form fields
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseDefaults();
  }

  void _parseDefaults() {
    defaultsList = [];
    
    if (widget.defaults is YamlMap) {
      widget.defaults.forEach((key, value) {
        defaultsList.add({
          'key': key,
          'value': value,
          'isExisting': true,
        });
      });
    } else if (widget.defaults is Map) {
      (widget.defaults as Map).forEach((key, value) {
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
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _addNewDefault() {
    setState(() {
      isAddingNew = true;
      _keyController.clear();
      _valueController.clear();
    });
  }

  void _saveDefault() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        defaultsList.add({
          'key': _keyController.text,
          'value': _valueController.text,
          'isExisting': false,
        });
        isAddingNew = false;
      });
    }
  }

  void _removeDefault(int index) {
    setState(() {
      defaultsList.removeAt(index);
    });
  }

  void _saveChanges() {
    // Convert back to defaults structure
    Map<String, dynamic> updatedDefaults = {};
    
    for (var def in defaultsList) {
      // Handle different value types properly
      final value = def['value'];
      if (value is String && value.contains('\n')) {
        // For multiline strings, preserve them as-is
        updatedDefaults[def['key']] = value;
      } else if (value is String && value.isNotEmpty) {
        // For simple strings, try to parse if they look like YAML
        try {
          final parsed = loadYaml(value);
          if (parsed != null) {
            updatedDefaults[def['key']] = parsed;
          } else {
            updatedDefaults[def['key']] = value;
          }
        } catch (e) {
          // If parsing fails, treat as simple string
          updatedDefaults[def['key']] = value;
        }
      } else {
        updatedDefaults[def['key']] = value;
      }
    }
    
    widget.onSave(updatedDefaults);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          
          // Defaults list
          Expanded(
            child: ListView.builder(
              itemCount: defaultsList.length,
              itemBuilder: (context, index) {
                final def = defaultsList[index];
                final key = def['key'];
                final value = def['value'];
                
                // Determine how to display the value
                Widget contentWidget;
                
                // Check if this is a complex structure that contains multiline content
                if (value is YamlMap || (value is Map && value.isNotEmpty)) {
                  // Handle complex nested structures
                  contentWidget = _buildComplexValueWidget(value);
                } else if (value is String && value.contains('\n')) {
                  // For multiline strings, apply card styling for better readability
                  contentWidget = Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  );
                } else if (value is List) {
                  // Handle lists
                  contentWidget = Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('List content:', style: TextStyle(fontWeight: FontWeight.bold)),
                        ...value.asMap().entries.map((entry) {
                          return Text('${entry.key}: ${entry.value}');
                        }).toList(),
                      ],
                    ),
                  );
                } else {
                  // For simple values, display as text
                  contentWidget = Text('$value');
                }
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Defaults for Snap: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('$key', style: const TextStyle(fontWeight: FontWeight.normal)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        contentWidget,
                        if (def['isExisting'] == true)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeDefault(index),
                                tooltip: 'Remove',
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
          
          // Add new default button
          if (!isAddingNew)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addNewDefault,
              tooltip: 'Add New Default',
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
                    controller: _keyController,
                    decoration: const InputDecoration(labelText: 'Key'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a key';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _valueController,
                    decoration: const InputDecoration(labelText: 'Value'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a value';
                      }
                      return null;
                    },
                    maxLines: null, // Allow multiline input
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
                        onPressed: _saveDefault,
                        child: const Text('Save Default'),
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

  Widget _buildComplexValueWidget(dynamic value) {
    if (value == null) {
      return const Text('null');
    }
    
    if (value is YamlMap || value is Map) {
      if (value.isEmpty) {
        return const Text('(empty)');
      }
      
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ...value.entries.map((entry) {
              final key = entry.key;
              final nestedValue = entry.value;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$key:'),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.only(left: 16),
                    width: double.infinity,
                    child: _buildValueForDisplay(nestedValue),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }).toList(),
          ],
        ),
      );
    }
    
    if (value is List) {
      if (value.isEmpty) {
        return const Text('(empty)');
      }
      
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('List content:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...value.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$index: '),
                        Expanded(
                          child: _buildValueForDisplay(item),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ],
        ),
      );
    }
    
    // Handle primitive values
    return Text('$value');
  }
  
  Widget _buildValueForDisplay(dynamic value) {
    if (value == null) {
      return const Text('null');
    }
    
    if (value is String && value.contains('\n')) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          value,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );
    }
    
    if (value is YamlMap || value is Map) {
      if (value.isEmpty) {
        return const Text('(empty)');
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ...value.entries.map((entry) {
            final key = entry.key;
            final nestedValue = entry.value;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$key:'),
                const SizedBox(height: 4),
                Container(
                  margin: const EdgeInsets.only(left: 16),
                  width: double.infinity,
                  child: _buildValueForDisplay(nestedValue),
                ),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        ],
      );
    }
    
    if (value is List) {
      if (value.isEmpty) {
        return const Text('(empty)');
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ...value.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$index: '),
                      Expanded(
                        child: _buildValueForDisplay(item),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ],
      );
    }
    
    // Handle primitive values
    return Text('$value');
  }
}
