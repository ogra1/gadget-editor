import 'package:flutter/material.dart';

import 'package:gadget_editor/services/gadget_yaml_service.dart';

class SimpleKernelCmdlineEditor extends StatefulWidget {
  /// The raw `kernel-cmdline` node as currently rendered by the display.
  ///
  /// The editor is add-only and its save path reads through the service, so
  /// this is held only for API compatibility with the display layer (mirrors
  /// how the ported connections/defaults editors keep their section-data
  /// field).
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
  State<SimpleKernelCmdlineEditor> createState() =>
      _SimpleKernelCmdlineEditorState();
}

class _SimpleKernelCmdlineEditorState extends State<SimpleKernelCmdlineEditor> {
  final _formKey = GlobalKey<FormState>();

  // Form fields
  final _parameterController = TextEditingController();
  final _valueController = TextEditingController();
  String _selectedType = 'allow'; // Default to allow

  @override
  void dispose() {
    _parameterController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  /// Builds the scalar to store: `parameter=value` when a value is given,
  /// otherwise the bare `parameter`.
  String _buildEntry(String parameter, String value) {
    return value.isEmpty ? parameter : '$parameter=$value';
  }

  /// Saves the entered kernel parameter through the service, which appends
  /// the entry to the selected `allow`/`append`/`remove` sub-list (creating
  /// the section on demand) and touches nothing else in the document.
  void _saveChangesToYaml() {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

    // Get form values
    final parameter = _parameterController.text.trim();
    final value = _valueController.text.trim();
    final type = _selectedType;

    // Validate inputs
    if (parameter.isEmpty) {
      widget.onStatusUpdate('Error: Please enter a parameter');
      return;
    }

    try {
      final yaml = GadgetYaml.fromFile(widget.filePath!);
      yaml.addKernelCmdlineItem(type, _buildEntry(parameter, value));
      yaml.save();

      // Show success message via status bar
      widget.onStatusUpdate('Kernel parameter added successfully');

      // Notify parent that changes were saved so it can refresh.
      widget.onSave(yaml.toMap()['kernel-cmdline']);

      // Clear form fields
      _parameterController.clear();
      _valueController.clear();
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
                      initialValue: _selectedType,
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
                      decoration: const InputDecoration(
                          labelText: 'Kernel parameter name'),
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
