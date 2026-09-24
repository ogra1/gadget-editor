import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import 'package:yaml_edit/yaml_edit.dart';

class PartitionSizeEditor extends StatefulWidget {
  final String partitionName;
  final String? currentSize;
  final String? filePath;
  final String volumeName;
  final Function(String) onSave;
  final Function() onCancel;
  final Function(String) onStatusUpdate;
  final Function()? onPartitionChanged;

  const PartitionSizeEditor({
    super.key,
    required this.partitionName,
    this.currentSize,
    this.filePath,
    required this.volumeName,
    required this.onSave,
    required this.onCancel,
    required this.onStatusUpdate,
    this.onPartitionChanged,
  });

  @override
  State<PartitionSizeEditor> createState() => _PartitionSizeEditorState();
}

class _PartitionSizeEditorState extends State<PartitionSizeEditor> {
  final _sizeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

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

  Future<void> _saveChangesToYaml() async {
    if (widget.filePath == null) {
      widget.onStatusUpdate('Error: No file path provided');
      return;
    }

    final newSize = _sizeController.text.trim();
    if (newSize.isEmpty) {
      widget.onStatusUpdate('Error: Please enter a size');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final file = File(widget.filePath!);
      final content = await file.readAsString();

      final yaml = loadYaml(content);
      final editor = YamlEditor(content);

      if (yaml is YamlMap && yaml.containsKey('volumes')) {
        final volumes = yaml['volumes'];
        
        if (volumes is YamlMap && volumes.containsKey(widget.volumeName)) {
          final volumeData = volumes[widget.volumeName];
          
          if (volumeData is YamlMap && volumeData.containsKey('structure')) {
            final structure = volumeData['structure'];
            
            if (structure is YamlList) {
              int targetIndex = -1;
              
              for (int i = 0; i < structure.length; i++) {
                final element = structure[i];
                if (element is YamlMap && element['name'] == widget.partitionName) {
                  targetIndex = i;
                  break;
                }
              }
              
              if (targetIndex != -1) {
                editor.update([
                  'volumes', 
                  widget.volumeName, 
                  'structure', 
                  targetIndex, 
                  'size'
                ], newSize);

                await file.writeAsString(editor.toString());
                
                if (!mounted) return;
                widget.onStatusUpdate('Partition size updated successfully to $newSize');
                widget.onSave(newSize);
                
                if (widget.onPartitionChanged != null) {
                  widget.onPartitionChanged!();
                }
                
                return;
              }
            }
          }
        }
      }
      
      if (!mounted) return;
      widget.onStatusUpdate('Error: Partition or volume structure not found.');

    } catch (e) {
      if (!mounted) return;
      widget.onStatusUpdate('Error saving changes: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Size for ${widget.partitionName}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _sizeController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Size',
                  hintText: 'e.g., 100M, 1G, 440, 1.5G',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a size';
                  }
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
          onPressed: _isSaving ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving
              ? null
              : () {
                  if (_formKey.currentState!.validate()) {
                    _saveChangesToYaml();
                  }
                },
          child: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
              : const Text('Save'),
        ),
      ],
    );
  }
}
