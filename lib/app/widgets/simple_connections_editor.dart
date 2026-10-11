import 'package:flutter/material.dart';

import 'package:gadget_editor/services/gadget_yaml_service.dart';
import 'package:gadget_editor/services/snap_lookup_service.dart';
import 'snap_id_field.dart';

class SimpleConnectionsEditor extends StatefulWidget {
  /// The raw `connections` node as currently rendered by the display.
  ///
  /// The editor is add-only and its save path reads through the service, so
  /// this is held only for API compatibility with the display layer (mirrors
  /// how the ported defaults editor keeps its section-data field).
  final dynamic connections;
  final String? filePath;
  final Function(dynamic) onSave;
  final Function() onCancel;
  final Function(String) onStatusUpdate;

  /// Resolver for the snap-ID fields. Defaults to the live store service;
  /// tests inject a fake so they stay hermetic.
  final SnapLookupService? lookupService;

  const SimpleConnectionsEditor({
    super.key,
    required this.connections,
    this.filePath,
    required this.onSave,
    required this.onCancel,
    required this.onStatusUpdate,
    this.lookupService,
  });

  @override
  State<SimpleConnectionsEditor> createState() => _SimpleConnectionsEditorState();
}

class _SimpleConnectionsEditorState extends State<SimpleConnectionsEditor> {
  final _formKey = GlobalKey<FormState>();

  // Form fields
  final _plugSnapIdController = TextEditingController();
  final _plugController = TextEditingController();
  final _slotSnapIdController = TextEditingController();
  final _slotController = TextEditingController();

  /// Smart snap-ID fields: they resolve a typed snap name to its store ID
  /// in place, and let the save path await any in-flight lookup.
  final GlobalKey<SnapIdFieldState> _plugSnapIdFieldKey = GlobalKey();
  final GlobalKey<SnapIdFieldState> _slotSnapIdFieldKey = GlobalKey();

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
      return true; // A blank snap ID means the "system" nick.
    }

    // Either the "system" nick (the spec's built-in reference) or a
    // full 32-character snap ID. The "system" nick is intentionally NOT
    // advertised anywhere in the UI.
    return snapId == 'system' || snapId.length == 32;
  }

  /// A snap ID must always be paired with its interface name. An interface
  /// on its own (no snap ID) is the common same-snap case and is valid, as is
  /// an empty pair (the slot is optional). Only a dangling snap ID — one with
  /// no interface to pair it with — is rejected.
  bool _validatePair(String? snapId, String? interface) {
    if (snapId != null && snapId.isNotEmpty) {
      return interface != null && interface.isNotEmpty;
    }
    return true;
  }

  /// Builds the connection map in the on-disk gadget.yaml format:
  ///
  /// ```yaml
  /// connections:
  ///   - plug: <plug snap id>:<plug interface>
  ///     slot: <slot snap id>:<slot interface>   # optional
  /// ```
  ///
  /// A missing snap ID yields a bare interface name (the same-snap case);
  /// a missing slot omits the `slot` key entirely.
  Map<String, dynamic> _buildConnectionFromForm(
    String plugSnapId,
    String plug,
    String slotSnapId,
    String slot,
  ) {
    final connection = <String, dynamic>{
      'plug': _qualified(plugSnapId, plug),
    };
    if (slot.isNotEmpty) {
      connection['slot'] = _qualified(slotSnapId, slot);
    }
    return connection;
  }

  /// Returns the on-disk endpoint form `<snap id>:<interface>`. A blank snap
  /// ID is qualified with the spec's "system" nick, so the value always
  /// carries an explicit snap reference (a bare interface name is not valid).
  String _qualified(String snapId, String interfaceName) {
    final id = snapId.isEmpty ? 'system' : snapId;
    return '$id:$interfaceName';
  }

  /// Saves the entered connection through the service, which appends the
  /// single entry to the top-level `connections` list (creating the section
  /// on demand) and touches nothing else in the document.
  ///
  /// Resolving snap names to IDs is awaited first: when the user typed a
  /// store name, the field already holds its ID; when it could not be
  /// resolved, the raw text is persisted as-is (manual ID fallback).
  Future<void> _saveChangesToYaml() async {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

    // Get form values (awaiting any in-flight name -> ID resolution).
    final plugSnapId =
        await _plugSnapIdFieldKey.currentState!.resolveForSave();
    final plug = _plugController.text.trim();
    final slotSnapId =
        await _slotSnapIdFieldKey.currentState!.resolveForSave();
    final slot = _slotController.text.trim();

    // Validate inputs
    if (plug.isEmpty) {
      widget.onStatusUpdate('Error: Please enter a plug');
      return;
    }

    // Validate snap ID formats
    if (plugSnapId.isNotEmpty && !_isValidSnapId(plugSnapId)) {
      widget.onStatusUpdate(
          'Error: Invalid plug snap ID format. Must be 32 characters');
      return;
    }

    if (slotSnapId.isNotEmpty && !_isValidSnapId(slotSnapId)) {
      widget.onStatusUpdate(
          'Error: Invalid slot snap ID format. Must be 32 characters');
      return;
    }

    // A snap ID, when given, must be paired with its interface name.
    if (!_validatePair(plugSnapId, plug)) {
      widget.onStatusUpdate('Error: Plug snap ID requires an interface name');
      return;
    }

    if (!_validatePair(slotSnapId, slot)) {
      widget.onStatusUpdate('Error: Slot snap ID requires an interface name');
      return;
    }

    final connection =
        _buildConnectionFromForm(plugSnapId, plug, slotSnapId, slot);

    try {
      final yaml = GadgetYaml.fromFile(widget.filePath!);
      yaml.addConnection(connection);
      yaml.save();

      // Show success message via status bar
      widget.onStatusUpdate('Connection added successfully');

      // Notify parent that changes were saved so it can refresh.
      widget.onSave(yaml.toMap()['connections']);

      // Clear form fields
      _plugSnapIdController.clear();
      _plugController.clear();
      _slotSnapIdController.clear();
      _slotController.clear();
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
                  const SizedBox(width: 16), // padding between label and field
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5, // more space to snap ID
                          child: SnapIdField(
                            key: _plugSnapIdFieldKey,
                            controller: _plugSnapIdController,
                            lookupService: widget.lookupService,
                            hint: 'Snap name or 32-character ID',
                            validator: (value) {
                              if (value != null &&
                                  value.isNotEmpty &&
                                  !_isValidSnapId(value)) {
                                return 'Invalid snap ID. Must be 32 characters.';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3, // less space to interface
                          child: TextFormField(
                            controller: _plugController,
                            decoration: const InputDecoration(
                                labelText: 'Interface Plug'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a plug';
                              }
                              // A snap ID, when given, needs an interface.
                              final plugSnapId =
                                  _plugSnapIdController.text.trim();
                              if (plugSnapId.isNotEmpty) {
                                return 'Snap ID requires an interface name';
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
                  const SizedBox(
                      width: 100, child: Text('Slot (optional):')),
                  const SizedBox(width: 16), // padding between label and field
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5, // more space to snap ID
                          child: SnapIdField(
                            key: _slotSnapIdFieldKey,
                            controller: _slotSnapIdController,
                            lookupService: widget.lookupService,
                            hint: 'Snap name or 32-character ID',
                            validator: (value) {
                              if (value != null &&
                                  value.isNotEmpty &&
                                  !_isValidSnapId(value)) {
                                return 'Invalid snap ID. Must be 32 characters.';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3, // less space to interface
                          child: TextFormField(
                            controller: _slotController,
                            decoration: const InputDecoration(
                                labelText: 'Interface Slot'),
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                // A snap ID, when given, needs an interface.
                                final slotSnapId =
                                    _slotSnapIdController.text.trim();
                                if (slotSnapId.isNotEmpty) {
                                  return 'Snap ID requires an interface name';
                                }
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
