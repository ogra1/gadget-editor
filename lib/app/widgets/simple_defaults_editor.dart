import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'package:gadget_editor/services/gadget_yaml_service.dart';

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
  final _formKey = GlobalKey<FormState>();

  // Form fields
  final _snapIdController = TextEditingController();
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  bool _isMultilineExpanded = false;
  final _multilineController = TextEditingController();

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

  /// Coerces the entered value into the YAML scalar it should become.
  ///
  /// Booleans, null and numbers become real scalars so they are written
  /// without quotes; a multiline value becomes a literal-style (block `|`)
  /// scalar; anything else stays a plain string.
  Object? _valueNodeFor(String value) {
    if (_isMultilineExpanded) {
      return wrapAsYamlNode(value, scalarStyle: ScalarStyle.LITERAL);
    }
    if (value == 'true') return true;
    if (value == 'false') return false;
    if (value == 'null') return null;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
      try {
        return value.contains('.') ? double.parse(value) : int.parse(value);
      } on FormatException {
        return value;
      }
    }
    return value;
  }

  /// Saves the entered default through the service, which writes only the
  /// single leaf (creating the nesting it needs); comments and everything
  /// else in the document survive.
  void _saveChangesToYaml() {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

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

    try {
      final yaml = GadgetYaml.fromFile(widget.filePath!);
      yaml.setDefault(snapId, key, _valueNodeFor(value));
      yaml.save();

      // Show success message via status bar
      widget.onStatusUpdate('Default added successfully');

      // Notify parent that changes were saved so it can refresh
      widget.onSave(yaml.toMap()['defaults']);

      // Clear form fields
      _snapIdController.clear();
      _keyController.clear();
      _valueController.clear();
      _multilineController.clear();
      setState(() {
        _isMultilineExpanded = false;
      });

    } on GadgetYamlException catch (e) {
      widget.onStatusUpdate('Error saving changes: ${e.message}');
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
                  child: TextFormField(
                    controller: _multilineController,
                    decoration: const InputDecoration(
                      hintText: 'Paste multiline text here...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(8),
                    ),
                    // A fixed maxLines (not null / not expands) is what makes
                    // the editable surface fill the fixed-height box instead of
                    // collapsing to a single line at the top. Content beyond
                    // the box scrolls within it.
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a value';
                      }
                      return null;
                    },
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
