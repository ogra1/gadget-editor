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
      updatedDefaults[def['key']] = def['value'];
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
               
                // Apply exact styling pattern that matches main pane
                Widget contentWidget;
                
                // Check if this is a complex structure that contains multiline content
                if (def['value'] is YamlMap) {
                  // Check for nested multiline content (like the LXD preseed example)
                  bool hasMultilineContent = false;
                  String multilineContent = '';
                  
                  // Look for nested structure that might contain multiline strings
                  def['value'].forEach((key, value) {
                    if (value is String && value.contains('\n')) {
                      hasMultilineContent = true;
                      multilineContent = value;
                    } else if (value is YamlMap) {
                      // Check nested YamlMap for multiline content
                      value.forEach((nestedKey, nestedValue) {
                        if (nestedValue is String && nestedValue.contains('\n')) {
                          hasMultilineContent = true;
                          multilineContent = nestedValue;
                        }
                      });
                    }
                  });
                  
                  if (hasMultilineContent) {
                    // Apply same card styling as main pane for multiline content
                    contentWidget = Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        multilineContent,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  } else {
                    // For complex structures without multiline content, show basic card
                    contentWidget = Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'YAML Structure',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }
                } else if (def['value'] is String && def['value'].contains('\n')) {
                  // For direct multiline strings, apply same card styling as main pane
                  contentWidget = Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      def['value'],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  );
                } else {
                  contentWidget = Text('Value: ${def['value'] ?? 'N/A'}');
                }
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default: ${def['key'] ?? 'Unnamed'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        contentWidget,
                        if (def['isExisting'] == true)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _removeDefault(index),
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
}
