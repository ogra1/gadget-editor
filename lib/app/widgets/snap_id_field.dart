import 'dart:async';

import 'package:flutter/material.dart';

import 'package:gadget_editor/services/snap_lookup_service.dart';

/// A snap-ID text field that transparently resolves a typed snap *name* to
/// its 32-character store *ID*.
///
/// While the user types, text that looks like a snap name (lowercase with
/// dashes, shorter than a snap ID) is looked up in the store (debounced).
/// When a snap is found, the field content is replaced by the snap ID and a
/// check mark appears in the suffix; when nothing is found, a small
/// "not found" indicator is shown and the text is kept as-is — which is the
/// intended fallback for unsearchable snaps whose ID is pasted manually.
///
/// The field keeps a plain [TextFormField] surface (label, controller,
/// validator) so existing form layouts are unaffected; the resolver only
/// adds a suffix icon and never an extra row.
class SnapIdField extends StatefulWidget {
  const SnapIdField({
    super.key,
    required this.controller,
    this.lookupService,
    this.validator,
    this.hint,
    this.onChanged,
  });

  final TextEditingController controller;

  /// Resolver to use; defaults to the live store service. Tests inject a
  /// fake-backed instance.
  final SnapLookupService? lookupService;

  /// External (format) validator, forwarded to the [TextFormField].
  final String? Function(String?)? validator;

  /// Placeholder shown inside the field (e.g. to advertise that a snap name
  /// can be typed instead of a 32-character ID). Rendered by [TextFormField]
  /// only while the field is empty, so it adds no extra row.
  final String? hint;

  /// Notified on every text change, including resolver-driven ones.
  final ValueChanged<String>? onChanged;

  @override
  State<SnapIdField> createState() => SnapIdFieldState();
}

/// Exposed state so a form's save path can call [resolveForSave] before
/// persisting the value.
class SnapIdFieldState extends State<SnapIdField> {
  /// Snap names are lowercase with dashes. Exactly-32-character values are
  /// treated as snap IDs (never looked up), and "system" is the spec's
  /// built-in nick (never a store snap).
  static final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$');

  /// Typing pause before a lookup fires, so a name typed letter by letter
  /// costs a single store round trip.
  static const Duration _debounce = Duration(milliseconds: 300);

  late final SnapLookupService _lookupService =
      widget.lookupService ?? SnapLookupService();

  /// Last successful resolution and the name it was resolved from.
  SnapLookup? _resolved;
  String? _resolvedName;

  /// Last name the store could not resolve (fallback indicator).
  String? _unresolvedName;

  Completer<void>? _pending;
  Timer? _debounceTimer;

  bool get _resolving => _pending != null;

  bool _isNameCandidate(String text) =>
      text.isNotEmpty &&
      text.length < 32 &&
      text != 'system' &&
      _namePattern.hasMatch(text) &&
      text != _resolvedName &&
      text != _unresolvedName;

  void _resetState() {
    _resolved = null;
    _resolvedName = null;
    _unresolvedName = null;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _resetState();
    super.dispose();
  }

  Future<void> _maybeResolve(String text) async {
    if (_pending != null) return;
    if (!_isNameCandidate(text)) return;

    _pending = Completer<void>();
    SnapLookup? result;
    try {
      result = await _lookupService.lookup(text);
    } catch (_) {
      result = null; // Network failures degrade to "unresolvable".
    } finally {
      _pending!.complete();
      _pending = null;
    }

    if (!mounted) return;

    final now = widget.controller.text.trim();
    if (now == text) {
      if (result != null) {
        _resolved = result;
        _resolvedName = text;
        // Replace the name with the resolved ID. This triggers onChanged,
        // but a snap ID never matches the name pattern, so no further
        // lookup is started.
        widget.controller.text = result.snapId;
      } else {
        _unresolvedName = text;
      }
      setState(() {});
    }

    // The text changed while the lookup was in flight: resolve the new text
    // now that this one has settled.
    if (now != text && now.isNotEmpty) {
      _debounceTimer?.cancel();
      scheduleMicrotask(() => _maybeResolve(now));
    }
  }

  /// Waits for any in-flight resolution and returns the value to persist:
  /// the resolved snap ID when available, otherwise the raw text (the
  /// manual-ID fallback for snaps the store does not know).
  Future<String> resolveForSave() async {
    _debounceTimer?.cancel();
    final pending = _pending;
    if (pending != null) {
      await pending.future;
    }
    final text = widget.controller.text.trim();
    if (text == _resolvedName && _resolved != null) {
      return _resolved!.snapId;
    }
    // The text was set without going through onChanged (or changed after
    // the last resolution): resolve it before saving.
    if (_isNameCandidate(text)) {
      await _maybeResolve(text);
    }
    return widget.controller.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      onChanged: (value) {
        if (value.trim().isEmpty) {
          _resetState();
          setState(() {});
        }
        widget.onChanged?.call(value);
        _debounceTimer?.cancel();
        final text = value.trim();
        if (_isNameCandidate(text)) {
          _debounceTimer = Timer(_debounce, () => _maybeResolve(text));
        }
      },
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: 'Snap ID',
        hintText: widget.hint,
        suffixIcon: _buildSuffixIcon(context),
      ),
    );
  }

  Widget _buildSuffixIcon(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = widget.controller.text.trim();

    if (_resolving) {
      return const Padding(
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_resolved != null && current == _resolved!.snapId) {
      final r = _resolved!;
      final meta = [
        if (r.publisher != null && r.publisher!.isNotEmpty) r.publisher,
        if (r.validation != null && r.validation!.isNotEmpty) r.validation,
      ].join(' · ');
      final headline = meta.isEmpty ? r.name : '${r.name} · $meta';
      return Tooltip(
        message: '$headline\nSnap ID: ${r.snapId}',
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(Icons.check_circle, size: 16, color: scheme.primary),
        ),
      );
    }

    if (_unresolvedName != null && current == _unresolvedName) {
      return Tooltip(
        message: 'Not found in the store — paste the snap ID manually.',
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(Icons.link_off, size: 16, color: scheme.onSurfaceVariant),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
