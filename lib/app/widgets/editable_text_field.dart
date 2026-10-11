import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// A compact, outlined, in-place editable text field.
///
/// In its resting state it renders as a compact outlined "chip" that hugs its
/// content (long values wrap onto extra lines rather than clipping). Tapping
/// it (or the pencil) expands the field in place to fill the row as a real
/// outlined [TextField]. Saving (check / Enter) commits via [onSave];
/// cancelling (X) reverts to the original value.
///
/// The editor also collapses whenever the user dismisses it without an
/// explicit save: pressing Escape, or moving focus away (clicking another
/// field, Tab, or the window losing focus). A dismissed edit is cancelled,
/// so the original value is restored and [onSave] is not invoked.
///
/// [label] is an optional caption (e.g. "Image Name"). At rest it is drawn as
/// a small caption above the chip; while editing it becomes the field's
/// floating label, mirroring the search field.
///
/// The public API is otherwise unchanged from the previous plain-text variant,
/// so the existing snap-name / volume-name call sites (including the reset
/// hook used for snap-name validation) keep working untouched.
class EditableTextField extends StatefulWidget {
  final String text;
  final Function(String) onSave;
  final Function(String)? onEditingChanged;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool enabled;
  final String? label;
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
    this.label,
    this.onStateCreated,
  });

  @override
  State<EditableTextField> createState() => _EditableTextFieldState();
}

class _EditableTextFieldState extends State<EditableTextField> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;
  late String _currentText;
  late String _originalText; // Store the original text for reset

  @override
  void initState() {
    super.initState();
    _currentText = widget.text;
    _originalText = widget.text;
    _controller = TextEditingController(text: _currentText);

    // Collapse when the user dismisses the editor without an explicit save:
    // Escape, or the field losing focus (another field focused, Tab, or the
    // window blurred). A dismissed edit reverts to the original value.
    _focusNode.addListener(_onFocusChange);
    _focusNode.onKeyEvent = _onEditorKey;

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
    _focusNode.dispose();
    super.dispose();
  }

  // Private reset method
  void _resetToOriginal() {
    setState(() {
      _currentText = _originalText;
      _controller.text = _currentText;
    });
  }

  /// Escape dismisses the editor (cancelling the in-progress edit).
  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (_isEditing &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Collapse when focus leaves the editor mid-edit. The [_isEditing] guard
  /// keeps this inert for the focus loss that follows an explicit save or
  /// cancel (when the field is already back to the chip), so only a genuine
  /// dismissal reverts the value.
  void _onFocusChange() {
    if (_isEditing && !_focusNode.hasFocus) {
      _cancel();
    }
  }


  void _startEditing() {
    if (!widget.enabled) {
      return;
    }
    _controller.text = _currentText;
    setState(() => _isEditing = true);
    // Give the frame a moment so the field is present before focusing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _save() {
    final value = _controller.text;
    setState(() {
      _isEditing = false;
      _currentText = value;
      // Deliberately NOT updating _originalText here: if [onSave] rejects
      // the value (e.g. invalid snap name), the caller invokes
      // resetToOriginal() (via onStateCreated) to revert the field.
      // Clobbering the original here would make that reset a no-op. On
      // success the parent round-trips the accepted value, which updates
      // _originalText through didUpdateWidget.
    });
    // Call the onSave callback with the new value
    widget.onSave(value);
  }

  void _cancel() {
    _controller.text = _originalText;
    setState(() {
      _isEditing = false;
      _currentText = _originalText;
    });
  }

  InputDecoration _editDecoration(ThemeData theme) {
    final base = widget.decoration ??
        const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        );
    return base.copyWith(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
            color: theme.colorScheme.primary, width: 1.5),
      ),
      labelText: widget.label,
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Cancel',
            onPressed: _cancel,
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 16),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isEditing) {
      // Expanded, in-place outlined editor that fills the available width.
      //
      // Only onSubmitted commits here: on a desktop Enter, Flutter fires both
      // onSubmitted and onEditingComplete, so registering both would save
      // twice (the second rename then fails on the already-renamed file).
      return TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: widget.style,
        textAlign: widget.textAlign ?? TextAlign.start,
        decoration: _editDecoration(theme),
        onChanged: (value) {
          _currentText = value;
          widget.onEditingChanged?.call(value);
        },
        onSubmitted: (_) => _save(),
        autofocus: true,
      );
    }

    // Resting state: a compact outlined chip that hugs its content. A Wrap
    // shrink-wraps for short values and wraps long ones onto extra lines
    // instead of clipping, so the chip always shows the full value.
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? _startEditing : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.dividerColor,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_currentText, style: widget.style),
            if (widget.enabled)
              Icon(
                Icons.edit,
                size: 14,
                color: theme.dividerColor,
              ),
          ],
        ),
      ),
    );

    final label = widget.label;
    if (label == null) {
      return chip;
    }

    // Optional caption above the chip (becomes the floating label on edit).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        chip,
      ],
    );
  }
}

// State class to provide external access to the widget's functionality
class EditableTextFieldState {
  final VoidCallback resetToOriginal;

  EditableTextFieldState(this.resetToOriginal);
}
