import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'package:gadget_editor/services/gadget_yaml_service.dart';

/// Free-form slot attribute row: one key/value pair with a remove button.
class _AttributeRow {
  final keyController = TextEditingController();
  final valueController = TextEditingController();

  _AttributeRow({String key = '', String value = ''}) {
    keyController.text = key;
    valueController.text = value;
  }

  /// True when both fields are blank; such rows are dropped on save.
  bool get isEmpty =>
      keyController.text.trim().isEmpty && valueController.text.trim().isEmpty;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

/// Popup editor for slot declarations (`slots` in `meta/snap.yaml`).
///
/// A slot is an interface declaration on the gadget snap itself, so — unlike
/// the other section editors — it lives in the *snap* file, not
/// `gadget.yaml`: [filePath] is the path to `meta/snap.yaml`.
///
/// [mode] is `add` for a new slot (name editable, [initialAttributes]
/// ignored) or `edit` to replace the full attribute map of the existing
/// slot [name] (name locked, current values pre-filled). Saving performs a
/// format-preserving edit through the [GadgetYaml] service, then reports
/// success via [onStatusUpdate] and triggers [onSave] so the parent can
/// re-read the file.
class SimpleSlotsEditor extends StatefulWidget {
  /// `add` or `edit`; anything else is treated as `add`.
  final String mode;
  final String? filePath;

  /// The existing slot's name (edit mode).
  final String? name;

  /// The existing slot's attributes, e.g. `{'interface': 'i2c',
  /// 'path': '/dev/i2c-0'}` (edit mode).
  final Map<String, dynamic>? initialAttributes;
  final Function() onSave;
  final Function() onCancel;
  final Function(String) onStatusUpdate;

  const SimpleSlotsEditor({
    super.key,
    this.mode = 'add',
    this.filePath,
    this.name,
    this.initialAttributes,
    required this.onSave,
    required this.onCancel,
    required this.onStatusUpdate,
  });

  /// Opens the slot editor as a dialog (mirrors the delete-confirmation
  /// dialog in [GadgetSection]). [data] is unused by the editor; it exists
  /// for API symmetry with the other section editors.
  static Future<void> show(
    BuildContext context, {
    required String? snapFilePath,
    required Function() onSaved,
    required Function(String) onStatusUpdate,
    String? name,
    Map<String, dynamic>? initialAttributes,
    dynamic data,
  }) {
    final dialogWidth = MediaQuery.of(context).size.width * 0.5;
    final isEdit = name != null;
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Slot' : 'Add Slot'),
          content: SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              child: SimpleSlotsEditor(
                mode: isEdit ? 'edit' : 'add',
                filePath: snapFilePath,
                name: name,
                initialAttributes: initialAttributes,
                onSave: () {
                  Navigator.of(context).pop();
                  onSaved();
                },
                onCancel: () => Navigator.of(context).pop(),
                onStatusUpdate: onStatusUpdate,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  State<SimpleSlotsEditor> createState() => _SimpleSlotsEditorState();
}

class _SimpleSlotsEditorState extends State<SimpleSlotsEditor> {
  /// Same conservative shape the service enforces on slot names: letters,
  /// digits, '.', '_' and '-', starting with a letter or digit.
  static final RegExp _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  final _nameController = TextEditingController();
  final _interfaceController = TextEditingController();
  late List<_AttributeRow> _rows;

  bool get _isEdit => widget.mode == 'edit';

  @override
  void initState() {
    super.initState();
    final attributes = widget.initialAttributes ?? const <String, dynamic>{};
    _nameController.text = widget.name ?? '';
    _interfaceController.text = attributes['interface']?.toString() ?? '';
    _rows = [
      // interface is the dedicated field above; the free-form rows carry
      // the remaining attributes (order preserved).
      for (final entry in attributes.entries)
        if (entry.key != 'interface' && entry.value != null)
          _AttributeRow(key: entry.key, value: entry.value.toString()),
    ];
    // A brand-new slot ships with one empty attribute row so the
    // free-form section is immediately usable (the user may also add more).
    if (_rows.isEmpty) _rows.add(_AttributeRow());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _interfaceController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_AttributeRow()));
  }

  void _removeRow(int index) {
    setState(() => _rows[index].dispose());
    _rows.removeAt(index);
  }

  /// Collects the form into the on-disk attribute map, or `null` when the
  /// input is invalid (the error is already reported to the status bar).
  Map<String, dynamic>? _buildAttributes() {
    final name = _nameController.text.trim();
    if (!_isEdit && (name.isEmpty || !_namePattern.hasMatch(name))) {
      widget.onStatusUpdate(
          'Error: Invalid slot name (allowed: letters, digits, ".", "_" and "-", starting with a letter or digit)');
      return null;
    }

    final interface = _interfaceController.text.trim();
    if (interface.isEmpty) {
      widget.onStatusUpdate('Error: Please enter an interface');
      return null;
    }

    final attributes = <String, dynamic>{'interface': interface};
    for (final row in _rows) {
      if (row.isEmpty) continue;
      final key = row.keyController.text.trim();
      final value = row.valueController.text.trim();
      if (!_namePattern.hasMatch(key)) {
        widget.onStatusUpdate(
            'Error: Invalid attribute name "$key" (allowed: letters, digits, ".", "_" and "-", starting with a letter or digit)');
        return null;
      }
      if (attributes.containsKey(key)) {
        widget.onStatusUpdate('Error: Attribute "$key" is already set');
        return null;
      }
      attributes[key] = value;
    }
    return attributes;
  }

  void _save() {
    final filePath = widget.filePath;
    if (filePath == null) {
      widget.onStatusUpdate('Error: No snap.yaml file path provided');
      return;
    }
    final name = _isEdit ? widget.name! : _nameController.text.trim();
    final attributes = _buildAttributes();
    if (attributes == null) return;

    try {
      final yaml = GadgetYaml.fromFile(filePath);
      if (_isEdit) {
        yaml.setSlot(name, attributes);
      } else {
        yaml.addSlot(name, attributes);
      }
      yaml.save();
      widget.onStatusUpdate(
          _isEdit ? 'Slot updated successfully' : 'Slot added successfully');
      widget.onSave();
    } on GadgetYamlException catch (e) {
      widget.onStatusUpdate('Error saving slot: ${e.message}');
    } catch (e) {
      widget.onStatusUpdate('Error saving slot: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Name:')),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Slot name', hintText: 'e.g. i2c-0'),
                enabled: !_isEdit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Interface:')),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _interfaceController,
                decoration: const InputDecoration(
                    labelText: 'Interface', hintText: 'e.g. serial-port'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 100, child: Text('Attributes:')),
            const SizedBox(width: 16),
            Expanded(
                child: Text('optional',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant))),
          ],
        ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const SizedBox(width: 116),
                Expanded(
                  child: TextFormField(
                    controller: _rows[i].keyController,
                    decoration: const InputDecoration(
                        labelText: 'Attribute', hintText: 'e.g. path'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _rows[i].valueController,
                    decoration: const InputDecoration(
                        labelText: 'Value', hintText: 'e.g. /dev/i2c-0'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 16),
                  tooltip: 'Remove attribute',
                  onPressed: () => _removeRow(i),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 116),
          child: TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(YaruIcons.plus, size: 16),
            label: const Text('Add attribute'),
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
              onPressed: _save,
              child: Text(_isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ],
    );
  }
}
