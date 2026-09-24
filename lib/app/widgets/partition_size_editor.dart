import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

class PartitionSizeEditor extends StatefulWidget {
  final String partitionName;
  final String? currentSize;
  final Function(String) onSave;
  final Function() onCancel;

  const PartitionSizeEditor({
    super.key,
    required this.partitionName,
    this.currentSize,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<PartitionSizeEditor> createState() => _PartitionSizeEditorState();
}

class _PartitionSizeEditorState extends State<PartitionSizeEditor> {
  final _sizeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _sizeController.text = widget.currentSize ?? '';
  }

  @override
  void dispose() {
    _sizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Size for ${widget.partitionName}'),
      content: SizedBox(
        width: 400, // Made it wider to match other dialogs
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _sizeController,
                decoration: const InputDecoration(
                  labelText: 'Size',
                  hintText: 'e.g., 100M, 1G, 440, 1.5G',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a size';
                  }
                  // Allow numbers with optional decimal point and optional units (M, G, K, B)
                  if (!RegExp(r'^\d+(\.\d+)?(M|G|K|B)?$').hasMatch(value)) {
                    return 'Please enter a valid size (e.g., 100M, 1G, 440, 1.5G)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onSave(_sizeController.text);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
