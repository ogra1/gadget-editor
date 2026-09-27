import 'package:flutter/material.dart';

class EditableTextField extends StatefulWidget {
  final String text;
  final Function(String) onSave;
  final Function(String)? onEditingChanged;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool enabled;
  final Function(EditableTextFieldState)? onStateCreated;

  const EditableTextField({
    super.key,
    required this.text,
    required this.onSave,
    this.onEditingChanged,
    this.decoration,
    this.style,
    this.textAlign,
    this.enabled = true,
    this.onStateCreated,
  });

  @override
  State<EditableTextField> createState() => _EditableTextFieldState();
}

class _EditableTextFieldState extends State<EditableTextField> {
  late TextEditingController _controller;
  bool _isEditing = false;
  late String _currentText;
  late String _originalText; // Store the original text for reset

  @override
  void initState() {
    super.initState();
    _currentText = widget.text;
    _originalText = widget.text;
    _controller = TextEditingController(text: _currentText);
    
    // Expose the state to parent widget
    widget.onStateCreated?.call(EditableTextFieldState(_resetToOriginal));
  }

  @override
  void didUpdateWidget(covariant EditableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update the text when the widget receives new text
    if (widget.text != oldWidget.text) {
      setState(() {
        _currentText = widget.text;
        _originalText = widget.text;
        _controller.text = _currentText;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Private reset method
  void _resetToOriginal() {
    setState(() {
      _currentText = _originalText;
      _controller.text = _currentText;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: widget.decoration ??
                  InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    contentPadding: EdgeInsets.zero,
                  ),
              style: widget.style,
              textAlign: widget.textAlign ?? TextAlign.start,
              onChanged: (value) {
                _currentText = value;
                widget.onEditingChanged?.call(value);
              },
              onSubmitted: (value) {
                setState(() {
                  _isEditing = false;
                });
                // Call the onSave callback with the new value
                widget.onSave(value);
              },
              autofocus: true,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 18),
            onPressed: () {
              final value = _controller.text;
              setState(() {
                _isEditing = false;
                _currentText = value;
              });
              // Call the onSave callback with the new value
              widget.onSave(value);
            },
            tooltip: 'Save',
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: widget.enabled ? () => setState(() => _isEditing = true) : null,
            child: Text(
              _currentText,
              style: widget.style,
              textAlign: widget.textAlign ?? TextAlign.start,
            ),
          ),
        ),
        if (widget.enabled)
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => setState(() => _isEditing = true),
            tooltip: 'Edit',
          ),
      ],
    );
  }
}

// State class to provide external access to the widget's functionality
class EditableTextFieldState {
  final VoidCallback resetToOriginal;
  
  EditableTextFieldState(this.resetToOriginal);
}