// Gadget YAML service
//
// Central, widget-free home for every mutation performed on a gadget.yaml.
//
// The engine is package:yaml_edit's YamlEditor, which edits the YAML as text
// and thereby preserves formatting, comments and key order. Every mutation
// goes through [GadgetYaml] so the "read file, edit, prune, write back"
// ritual that used to be copy-pasted across the UI widgets lives in exactly
// one place and is unit-testable without any Flutter import.
//
// Fallback rule
// -------------
// A [GadgetYaml] is either *file-backed* (constructed from a path on disk) or
// *string-backed* (constructed from an in-memory document, e.g. a snap that
// is still being staged in a temp directory). The two behave identically for
// everything except persistence:
//
//   * Mutations always apply to the in-memory [YamlEditor] first.
//   * For a file-backed instance, [save] writes the result back to the file
//     and re-reads it, so the file is the source of truth after every save.
//   * For a string-backed instance, [save] is a no-op and [toYaml] simply
//     returns the mutated in-memory text; the caller owns persistence.
//
// This keeps the service free of Flutter and trivially testable with both
// plain strings and temp files.
//
// yaml_edit quirks worked around here
// -----------------------------------
//  * `update` does not create intermediate maps. [update] builds the missing
//    nesting explicitly, in block style.
//  * A freshly constructed empty `YamlMap()`/`YamlList()` renders in *flow*
//    style (`{}` / `[]`) and taints its parent into flow style. No
//    intermediate is ever left empty, and [toYaml] collapses the degenerate
//    whole-document case to a blank string.
//  * A `YamlMap` that becomes empty switches its style to flow. `renameVolume`
//    therefore inserts the new key *before* removing the old one, so the
//    `volumes` map is never empty mid-operation.
//  * `update` inserts a *new* map key at its sorted position when the map's
//    keys are already sorted (which every shipped gadget.yaml is). That would
//    silently reorder the user's file (e.g. a new top-level `defaults`
//    landing above `name`). [_insertNewKey] therefore appends new keys at
//    the end of their parent map instead; existing keys are still replaced
//    in place.

import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

// yaml_edit's public API does not expose the error types it throws, nor the
// block-style collection wrappers we need to force block-style output. Both
// are stable internals and are the only reliable way to work around the
// library's flow-style rendering of freshly created collections.
// ignore: implementation_imports
import 'package:yaml_edit/src/errors.dart' show AliasException, PathError;
// ignore: implementation_imports
import 'package:yaml_edit/src/utils.dart' show getContentSensitiveEnd;
// ignore: implementation_imports
import 'package:yaml_edit/src/wrap.dart' show YamlListWrap, YamlMapWrap;

/// Thrown for any failure while loading, mutating or saving a gadget YAML:
/// unparseable input, a missing path, an out-of-bounds index, or a rejected
/// [YamlEditor] edit.
class GadgetYamlException extends FormatException {
  /// The underlying error, when there is one.
  final Object? cause;

  GadgetYamlException(super.message, [this.cause]);

  @override
  String toString() => cause == null
      ? 'GadgetYamlException: $message'
      : 'GadgetYamlException: $message (caused by: $cause)';
}

/// A single, mutable gadget.yaml document.
///
/// Construct via [GadgetYaml.fromContent] or [GadgetYaml.fromFile], then
/// mutate through the typed helpers ([setSnapName], [removeDefault], ...),
/// pass-throughs ([update], [remove], [appendToList], [insertIntoList]) or
/// the generic [mutate]. Read the current text with [toYaml]; persist a
/// file-backed document with [save].
class GadgetYaml {
  YamlEditor _editor;

  /// Absolute path of the backing file, or `null` for an in-memory document.
  final String? _filePath;

  GadgetYaml._(YamlEditor editor, String? filePath)
      : _editor = editor,
        _filePath = filePath;

  /// Parses [content] as YAML.
  ///
  /// Throws [GadgetYamlException] if [content] is not valid YAML.
  factory GadgetYaml.fromContent(String content) {
    try {
      return GadgetYaml._(YamlEditor(content), null);
    } on YamlException catch (e) {
      throw GadgetYamlException('Invalid gadget YAML: ${e.message}', e);
    } on FormatException catch (e) {
      throw GadgetYamlException('Invalid gadget YAML: ${e.message}', e);
    }
  }

  /// Reads and parses the file at [filePath].
  ///
  /// The returned instance is file-backed: [save] writes back to [filePath].
  /// Throws [GadgetYamlException] if the file cannot be read or is not valid
  /// YAML.
  factory GadgetYaml.fromFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw GadgetYamlException('Gadget YAML file not found: $filePath');
    }
    String content;
    try {
      content = file.readAsStringSync();
    } catch (e) {
      throw GadgetYamlException('Could not read $filePath', e);
    }
    try {
      return GadgetYaml._(YamlEditor(content), filePath);
    } on YamlException catch (e) {
      throw GadgetYamlException(
          'Invalid gadget YAML in $filePath: ${e.message}', e);
    }
  }

  /// Whether this instance is backed by a file on disk.
  bool get isFileBacked => _filePath != null;

  /// The backing file path, if any.
  String? get filePath => _filePath;

  /// The current YAML text.
  ///
  /// For a file-backed instance this is the (possibly mutated) in-memory
  /// state; call [save] to persist it to disk.
  String toYaml() => _normalize(_editor.toString());

  /// Collapses the flow-style markers for empty top-level collections
  /// (`{}` / `[]`) to a blank document, which they are equivalent to.
  static String _normalize(String yaml) {
    final trimmed = yaml.trim();
    if (trimmed == '{}' || trimmed == '[]') return '';
    return yaml;
  }

  /// Writes the current state back to the backing file and re-reads it.
  ///
  /// For a string-backed instance this is a no-op. Returns the persisted
  /// text (identical to [toYaml]). Throws [GadgetYamlException] on I/O
  /// failure.
  String save() {
    final filePath = _filePath;
    if (filePath == null) return toYaml();
    final content = toYaml();
    try {
      File(filePath).writeAsStringSync(content);
    } catch (e) {
      throw GadgetYamlException('Could not write $filePath', e);
    }
    _reload();
    return toYaml();
  }

  /// Re-reads the source of this document from disk, discarding any unsaved
  /// in-memory mutations.
  ///
  /// For a string-backed instance this is a no-op.
  void reload() {
    final filePath = _filePath;
    if (filePath == null) return;
    _reload();
  }

  void _reload() {
    final filePath = _filePath!;
    String content;
    try {
      content = File(filePath).readAsStringSync();
    } catch (e) {
      throw GadgetYamlException('Could not re-read $filePath', e);
    }
    try {
      _editor = YamlEditor(content);
    } on YamlException catch (e) {
      throw GadgetYamlException(
          'Invalid gadget YAML in $filePath after re-read: ${e.message}', e);
    }
  }

  // ---------------------------------------------------------------------
  // Generic, format-preserving mutation pass-throughs
  // ---------------------------------------------------------------------

  /// Sets the value at [path] (e.g. `['defaults', 'core20', 'x']`).
  ///
  /// Missing intermediate *maps* are created on demand in block style. List
  /// segments of the path must already exist (an index into a list is
  /// accepted, a key under a list is not). The mutation applies to the
  /// in-memory editor only — call [save] to persist a file-backed document.
  void update(List<Object?> path, Object? value) {
    if (path.isEmpty) {
      throw GadgetYamlException('Cannot replace the whole document via update');
    }
    _guard(() {
      // Find the deepest existing prefix of the path. The walk only extends
      // past prefixes that resolve to a container, so a path descending
      // through a scalar stops there and the scalar gets replaced by the
      // new nesting below.
      var depth = 1;
      while (depth < path.length &&
          _acceptsMorePath(path.sublist(0, depth), path[depth])) {
        depth++;
      }
      if (depth == path.length) {
        // The walk only validates segments *before* the last one, so the
        // last segment still needs a membership check.
        final parentPath = path.sublist(0, path.length - 1);
        final parent = nodeAt(parentPath);
        if (parent is YamlList) {
          // The index was validated by the walk: in-place replacement.
          _editor.update(path, _blockNode(value));
          return;
        }
        if (parent is YamlMap) {
          if (parent.containsKey(path.last)) {
            // Leaf (and all parents) exist: plain in-place update.
            _editor.update(path, _blockNode(value));
            return;
          }
          // The key is absent: append it at the end of the parent map.
          _insertNewKey(
              parentPath,
              YamlMapWrap({path.last: _blockNode(value)},
                  collectionStyle: CollectionStyle.BLOCK));
          return;
        }
        throw GadgetYamlException(
            "Cannot update the missing path '${path.join('.')}'");
      }
      // The walk stopped at [depth]; the deepest prefix resolves to one of:
      // a map that lacks the next key, a key absent from its parent map, a
      // list that cannot host a key, or a key that exists with a
      // null/scalar value.
      final deepest = path.sublist(0, depth);
      final built = _buildNestedValue(path.sublist(depth), value);
      final stopNode = nodeAt(deepest);
      if (stopNode is YamlMap) {
        // The map exists but lacks [path[depth]]: append the new entry at
        // the end of the map (see [_insertNewKey]).
        _insertNewKey(deepest, built as YamlMap);
      } else if (stopNode == null) {
        // [deepest] resolves to null: either the key is absent from its
        // parent map, or it exists with a null value.
        final containerPath = path.sublist(0, depth - 1);
        final container = nodeAt(containerPath);
        if (container is YamlList) {
          throw GadgetYamlException(
              "Cannot create a key under the list at '${containerPath.join('.')}'");
        }
        if (container is YamlMap && container.containsKey(deepest.last)) {
          // The key exists with a null value: replace its value in place
          // so the key keeps its position in the file.
          _editor.update(deepest, built);
        } else {
          // The key is absent: append the entry under it, keeping the
          // parent's order intact.
          _insertNewKey(
              containerPath,
              YamlMapWrap({deepest.last: built},
                  collectionStyle: CollectionStyle.BLOCK));
        }
      } else {
        // [deepest.last] exists with a null or scalar value: replace its
        // value in place so the key keeps its position in the file.
        _editor.update(deepest, built);
      }
    });
  }

  /// Inserts the new top-level entry [builtEntry] (a single-key block-style
  /// map) into the map at [parentPath], appended at the *end* of that map.
  ///
  /// yaml_edit's `update` would place the key at its *sorted* position when
  /// the map's keys are already sorted (every shipped gadget.yaml), which
  /// would reorder the user's file. There is no public insert-position API,
  /// so the entry is rendered with a throwaway editor (reusing yaml_edit's
  /// own block renderer), re-indented to the parent's depth and spliced
  /// into the document text after the parent's last entry. The editor is
  /// then re-wrapped: pending edits are applied eagerly to the text, and
  /// every span is recomputed from the new text, so nothing is lost.
  void _insertNewKey(List<Object?> parentPath, YamlMap builtEntry) {
    final parent = nodeAt(parentPath);
    if (parent is! YamlMap || parent.isEmpty) {
      throw GadgetYamlException(
          "Cannot add a key to the map at '${parentPath.join('.')}' "
          '(missing or empty)');
    }
    // Render the entry in block style (key at indent 0, children at the
    // probe's default step of 2).
    final probe = YamlEditor('');
    probe.update([], builtEntry);
    final probeText = probe.toString();
    final docText = _editor.toString();

    final parentKey = parent.nodes.keys.first as YamlNode;
    final pkOffset = parentKey.span.start.offset;
    final lineStart = docText.lastIndexOf('\n', pkOffset) + 1;
    final parentKeyLine = docText.substring(lineStart, pkOffset);
    final keyIndent = parentKeyLine.length - parentKeyLine.trimLeft().length;
    // The document's indentation step: the first key of the parent map's
    // first map-valued child sits exactly one step deeper than the parent's
    // own keys. Falls back to 2 when no such child exists.
    YamlNode? firstChildKey;
    for (final childValue in parent.nodes.values) {
      if (childValue is YamlMap && childValue.isNotEmpty) {
        firstChildKey = childValue.nodes.keys.first as YamlNode;
        break;
      }
    }
    var docStep = 2;
    if (firstChildKey != null) {
      final firstChildLine =
          docText.substring(firstChildKey.span.start.offset).split('\n').first;
      final childIndent =
          firstChildLine.length - firstChildLine.trimLeft().length;
      if (childIndent > keyIndent) docStep = childIndent - keyIndent;
    }

    // Re-indent the probe text: the key line goes at the parent's depth,
    // deeper lines scale from the probe step (2) to the document's step.
    final lines = probeText.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].isEmpty) continue;
      final probeIndent = lines[i].length - lines[i].trimLeft().length;
      final indent = keyIndent + (i == 0 ? 0 : (probeIndent ~/ 2) * docStep);
      lines[i] = ' ' * indent + lines[i].substring(probeIndent);
    }
    final entry = lines.join('\n');

    // The new key goes at the end of the parent map: the first line after
    // the parent's last value. A block map's entries all end by then, so
    // the next line is outside the parent (an ancestor-level key or EOF)
    // regardless of where the parent sits in the document.
    final lastValueEnd = getContentSensitiveEnd(parent.nodes.values.last);
    final nextNewline = docText.indexOf('\n', lastValueEnd);
    final offset = nextNewline == -1 ? docText.length : nextNewline + 1;
    final before = docText.substring(0, offset);
    final after = docText.substring(offset);
    final newline = docText.contains('\r\n') ? '\r\n' : '\n';
    final lead = before.isEmpty || before.endsWith(newline) ? '' : newline;
    final trail = after.isNotEmpty && !after.startsWith(newline) ? newline : '';
    var newText = before + lead + entry + trail + after;
    if (!newText.endsWith(newline)) newText += newline;
    try {
      _editor = YamlEditor(newText);
    } on FormatException catch (e) {
      throw GadgetYamlException('Failed to insert entry: ${e.message}');
    }
  }

  /// Wraps a plain Dart list or map into a *block*-style [YamlNode].
  ///
  /// yaml_edit wraps plain collections in "any" style, which renders lists
  /// in flow style (`[a, b]`) on insertion. Gadget documents are block
  /// style, so we force that here.
  YamlNode _blockNode(Object? value) {
    if (value is List) {
      return YamlListWrap(
        value,
        collectionStyle: CollectionStyle.BLOCK,
      );
    }
    if (value is Map) {
      return YamlMapWrap(
        value,
        collectionStyle: CollectionStyle.BLOCK,
      );
    }
    return wrapAsYamlNode(value);
  }

  /// Builds a nested block-style collection from [keys] (deepest first)
  /// around [leaf].
  YamlNode _buildNestedValue(List<Object?> keys, Object? leaf) {
    YamlNode value = _blockNode(leaf);
    for (var i = keys.length - 1; i >= 0; i--) {
      value = YamlMapWrap(
        {keys[i]: value},
        collectionStyle: CollectionStyle.BLOCK,
      );
    }
    return value;
  }

  /// Removes the node at [path].
  ///
  /// Unlike [update], every element of [path] must already exist, otherwise
  /// a [GadgetYamlException] is thrown.
  void remove(List<Object?> path) => _guard(() => _editor.remove(path));

  /// Appends [value] to the list at [path].
  ///
  /// The list at [path] must already exist; creating it is the caller's
  /// job (the typed operations do so by routing through [update], which
  /// appends the new key at the end of its parent map).
  void appendToList(List<Object?> path, Object? value) {
    _guard(() {
      _ensureParentMaps(path);
      _editor.appendToList(path, value);
    });
  }

  /// Inserts [value] into the list at [path] at position [index].
  ///
  /// The list at [path] must already exist; creating it is the caller's
  /// job (see [appendToList]).
  void insertIntoList(List<Object?> path, int index, Object? value) {
    if (path.isEmpty) {
      return _guard(() => _editor.insertIntoList(path, index, value));
    }
    _guard(() {
      _ensureParentMaps(path);
      _editor.insertIntoList(path, index, value);
    });
  }

  /// Runs an arbitrary batch of edits against the raw [YamlEditor] inside a
  /// single guarded call. Use this only for edits on nodes that already
  /// exist — [update] (with its intermediate creation) is the safer
  /// primitive for new nesting.
  ///
  /// Note: [YamlEditor] applies each edit eagerly, so if a later step fails
  /// the earlier steps are already reflected in [toYaml]. Call [reload] to
  /// discard them on a file-backed document.
  void mutate(void Function(YamlEditor editor) edits) =>
      _guard(() => edits(_editor));

  /// Shallow view of the document for *display*: top-level keys are
  /// `String`s, but the values keep their `YamlMap`/`YamlList` types.
  ///
  /// This matches what the display widgets are written against (they
  /// pattern-match on the Yaml types). Mutations should go through the
  /// typed operations, never through this view.
  Map<String, dynamic> view() {
    final root = _editor.parseAt(const []).value;
    final result = <String, dynamic>{};
    if (root is YamlMap) {
      for (final entry in root.nodes.entries) {
        result[entry.key.value.toString()] = entry.value;
      }
    }
    return result;
  }

  /// Deep-converts the current document to plain Dart collections
  /// (`Map<String, dynamic>` / `List<dynamic>` / scalars), safe to hand to
  /// widgets that must not see `YamlMap`/`YamlList` types.
  Map<String, dynamic> toMap() {
    final root = _editor.parseAt(const []).value;
    final result = _convert(root);
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{};
  }

  /// Whether a node exists at [path].
  bool has(List<Object?> path) => nodeAt(path) != null;

  /// The value at [path], or `null` if the path does not exist.
  dynamic valueAt(List<Object?> path) => nodeAt(path)?.value;

  /// The raw [YamlNode] at [path], or `null` if the path does not exist.
  ///
  /// The walk is strict: every proper prefix must resolve to a container
  /// (a map for a key segment, a list for an in-range index segment), so a
  /// path that descends through a scalar is reported as missing rather than
  /// half-resolved.
  ///
  /// A document-level explicit `null` value is indistinguishable from a
  /// missing path by construction and is reported as "missing"; gadget.yaml
  /// documents never use this form.
  YamlNode? nodeAt(List<Object?> path) {
    var node = _rootNode();
    for (final segment in path) {
      if (node is YamlMap) {
        if (!node.containsKey(segment)) return null;
        // .nodes gives the raw YamlNode; [] unwraps to plain Dart values.
        node = node.nodes[segment] as YamlNode;
      } else if (node is YamlList) {
        if (segment is! int || segment < 0 || segment >= node.length) {
          return null;
        }
        node = node.nodes[segment];
      } else {
        // A scalar cannot host further path segments.
        return null;
      }
    }
    if (node is YamlScalar && node.value == null) return null;
    return node;
  }

  /// The parsed document root.
  YamlNode _rootNode() => _editor.parseAt(const []).value;

  /// True if the node at [prefix] can host the path segment [next] beneath
  /// it (a map hosts any key; a list only an in-range index).
  bool _acceptsMorePath(List<Object?> prefix, Object? next) {
    final node = nodeAt(prefix);
    if (node is YamlMap) return node.containsKey(next);
    if (node is YamlList) {
      return next is int && next >= 0 && next < node.length;
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Typed gadget.yaml operations
  // ---------------------------------------------------------------------

  /// Sets the top-level `name` key (snap rename).
  void setSnapName(String name) => update(const ['name'], name);

  /// Removes the [key] entry from the top-level `defaults` section.
  ///
  /// When `defaults` becomes empty the whole section is pruned as well.
  /// Throws [GadgetYamlException] if `defaults` or [key] does not exist.
  void removeDefault(String key) {
    if (!has(const ['defaults'])) {
      throw GadgetYamlException("No 'defaults' section in gadget YAML");
    }
    final defaults = nodeAt(const ['defaults']);
    if (defaults is! YamlMap || !defaults.containsKey(key)) {
      throw GadgetYamlException("No entry '$key' in the 'defaults' section");
    }
    _guard(() {
      _editor.remove(['defaults', key]);
      if (_isEmptyMapAt(const ['defaults'])) _editor.remove(const ['defaults']);
    });
  }

  /// Removes one setting from `defaults[snapId]`.
  ///
  /// [entry] identifies the setting *within* the snap ID's value: a
  /// top-level map key (e.g. `hold` in `defaults.core20.hold`) when the
  /// snap ID holds a map of settings, or an index when it holds a flat
  /// list. It is deliberately *not* a dot-separated path, so deleting one
  /// setting never reaches across the nesting. When the removal leaves the
  /// snap ID empty, the whole snap-ID entry is pruned as well, and when no
  /// snap IDs remain the `defaults` section goes with them.
  ///
  /// Throws [GadgetYamlException] if the section, snap ID or setting does
  /// not exist, or if the snap ID's value is a scalar (which must be
  /// deleted as a whole via [removeDefault]).
  void removeDefaultEntry(String snapId, Object? entry) {
    final defaults = nodeAt(const ['defaults']);
    if (defaults is! YamlMap) {
      throw GadgetYamlException("No 'defaults' section in gadget YAML");
    }
    if (!defaults.containsKey(snapId)) {
      throw GadgetYamlException("No entry '$snapId' in the 'defaults' section");
    }
    final entryNode = nodeAt(['defaults', snapId]);
    if (entryNode is YamlMap) {
      // A map of settings: the entry is a top-level key (String).
      if (entry is! String || !entryNode.containsKey(entry)) {
        throw GadgetYamlException(
            "No setting '$entry' under the '$snapId' defaults");
      }
      _guard(() {
        _editor.remove(['defaults', snapId, entry]);
        _pruneEmptiedDefaults(snapId);
      });
      return;
    }
    if (entryNode is YamlList) {
      // A flat list of settings: the entry is an in-range index.
      if (entry is! int || entry < 0 || entry >= entryNode.length) {
        throw GadgetYamlException(
            "No setting at index $entry under the '$snapId' defaults");
      }
      _guard(() {
        _editor.remove(['defaults', snapId, entry]);
        _pruneEmptiedDefaults(snapId);
      });
      return;
    }
    throw GadgetYamlException(
        "The '$snapId' default is a scalar; delete it as a whole instead");
  }

  /// Removes the snap-ID entry — and, if it leaves `defaults` empty, the
  /// section itself — after a single-setting removal emptied it.
  void _pruneEmptiedDefaults(String snapId) {
    if (_isEmptyMapAt(['defaults', snapId]) ||
        _isEmptyListAt(['defaults', snapId])) {
      _editor.remove(['defaults', snapId]);
    }
    if (_isEmptyMapAt(const ['defaults'])) {
      _editor.remove(const ['defaults']);
    }
  }

  /// Sets the value at `defaults[snapId][key]`, creating any missing
  /// nesting on demand. [key] may be dot-separated (e.g. `foo.bar.baz`);
  /// an existing scalar on the path is replaced by the new nesting.
  ///
  /// [value] is either a plain Dart scalar or a pre-built [YamlNode] (for
  /// example a literal-style multiline scalar); it is inserted verbatim and
  /// nothing else in the document is touched.
  ///
  /// Throws [GadgetYamlException] for an empty [snapId] or a [key] with an
  /// empty dot-separated part.
  void setDefault(String snapId, String key, Object? value) {
    if (snapId.isEmpty) {
      throw GadgetYamlException('Cannot set a default under an empty snap ID');
    }
    final keyParts = key.split('.');
    if (keyParts.any((part) => part.isEmpty)) {
      throw GadgetYamlException(
          "Invalid default key '$key' (empty dot-separated part)");
    }
    update(['defaults', snapId, ...keyParts], value);
  }

  /// Removes the [index]th entry from the top-level `connections` list.
  ///
  /// When `connections` becomes empty the whole section is pruned as well.
  void removeConnection(int index) {
    if (!has(const ['connections'])) {
      throw GadgetYamlException("No 'connections' section in gadget YAML");
    }
    final connections = nodeAt(const ['connections']);
    if (connections is! YamlList) {
      throw GadgetYamlException("'connections' section is not a list");
    }
    if (index < 0 || index >= connections.length) {
      throw GadgetYamlException(
          "Connection index $index out of range (0..${connections.length - 1})");
    }
    _guard(() {
      _editor.remove(['connections', index]);
      if (_isEmptyListAt(const ['connections'])) {
        _editor.remove(const ['connections']);
      }
    });
  }

  /// Adds [connection] — an entry in the combined gadget.yaml format
  /// `{'plug': <snap id>:<interface>}` with an optional
  /// `{'slot': <snap id>:<interface>}` key — to the end of the top-level
  /// `connections` list. The section is created on demand.
  void addConnection(Map<String, dynamic> connection) {
    if (!has(const ['connections'])) {
      // Route through [update] so the new top-level section is appended at
      // the end of the document, not sorted into place. A bare empty list
      // would render as flow `[]`, so seed the section with the entry.
      update(const ['connections'], [connection]);
      return;
    }
    _guard(() => _editor.appendToList(const ['connections'], connection));
  }

  /// Removes the [index]th entry of [section] (`allow`, `append` or
  /// `remove`) within the top-level `kernel-cmdline` section.
  ///
  /// Empty sub-sections are pruned, and `kernel-cmdline` itself is pruned
  /// once all of its sub-sections are gone. Returns the number of levels
  /// removed (1, 2 or 3).
  int removeKernelCmdlineItem(String section, int index) {
    const validSections = {'allow', 'append', 'remove'};
    if (!validSections.contains(section)) {
      throw GadgetYamlException(
          "Invalid kernel-cmdline section '$section' (expected one of ${validSections.join(', ')})");
    }
    if (!has(const ['kernel-cmdline'])) {
      throw GadgetYamlException("No 'kernel-cmdline' section in gadget YAML");
    }
    final sectionNode = nodeAt(['kernel-cmdline', section]);
    if (sectionNode is! YamlList || sectionNode.length <= index) {
      throw GadgetYamlException(
          "No item at index $index in 'kernel-cmdline.$section'");
    }
    var removedLevels = 0;
    _guard(() {
      _editor.remove(['kernel-cmdline', section, index]);
      removedLevels++;
      if (_isEmptyListAt(['kernel-cmdline', section])) {
        _editor.remove(['kernel-cmdline', section]);
        removedLevels++;
      }
      if (_kernelCmdlineFullyEmpty()) {
        _editor.remove(const ['kernel-cmdline']);
        removedLevels++;
      }
    });
    return removedLevels;
  }

  /// Appends [value] to the [section] list (`allow`, `append` or `remove`)
  /// under the top-level `kernel-cmdline` section, creating the section as
  /// needed.
  void addKernelCmdlineItem(String section, Object value) {
    const validSections = {'allow', 'append', 'remove'};
    if (!validSections.contains(section)) {
      throw GadgetYamlException(
          "Invalid kernel-cmdline section '$section' (expected one of ${validSections.join(', ')})");
    }
    if (!has(const ['kernel-cmdline'])) {
      // Whole section missing: route through [update] so the intermediate
      // `kernel-cmdline` map is created in block style.
      update(['kernel-cmdline', section], [value]);
      return;
    }
    if (!has(['kernel-cmdline', section])) {
      // Route through [update] so the new sub-section is appended at the
      // end of the kernel-cmdline map, not sorted into place.
      update(['kernel-cmdline', section], [value]);
      return;
    }
    _guard(() => _editor.appendToList(['kernel-cmdline', section], value));
  }

  /// Updates the `size` field of the partition named [partitionName] inside
  /// the volume [volumeName].
  void updatePartitionSize(
      String volumeName, String partitionName, String size) {
    if (!has(['volumes', volumeName])) {
      throw GadgetYamlException("No volume named '$volumeName'");
    }
    final structureNode = nodeAt(['volumes', volumeName, 'structure']);
    if (structureNode is! YamlList) {
      throw GadgetYamlException("Volume '$volumeName' has no 'structure' list");
    }
    final index = _findPartitionIndex(structureNode, partitionName);
    if (index == null) {
      throw GadgetYamlException(
          "No partition named '$partitionName' in volume '$volumeName'");
    }
    _guard(() => _editor
        .update(['volumes', volumeName, 'structure', index, 'size'], size));
  }

  /// Renames the top-level volume [oldName] to [newName], preserving the
  /// volume's content, comments and formatting.
  ///
  /// The new key is inserted *before* the old one is removed so that the
  /// `volumes` map never becomes empty mid-operation (an empty [YamlMap]
  /// would flip to flow style and re-emit the whole section as `{...}`).
  ///
  /// Throws if [oldName] does not exist or [newName] is already taken.
  void renameVolume(String oldName, String newName) {
    if (oldName == newName) return;
    if (!has(['volumes', oldName])) {
      throw GadgetYamlException("No volume named '$oldName'");
    }
    if (has(['volumes', newName])) {
      throw GadgetYamlException("A volume named '$newName' already exists");
    }
    _guard(() {
      final value = _editor.parseAt(['volumes', oldName]);
      // Insert the new key at the end of the volumes map (an in-place
      // yaml_edit update would sort it into position and reorder the
      // file), then drop the old one. The map is never empty mid-operation.
      _insertNewKey(const [
        'volumes'
      ], YamlMapWrap({newName: value}, collectionStyle: CollectionStyle.BLOCK));
      _editor.remove(['volumes', oldName]);
    });
  }

  /// The value of the `MODEL_APIKEY` environment variable configured for the
  /// `prepare-device` hook, or `null` when the hook or the key is absent.
  ///
  /// The `prepare-device` hook runs on first boot of an Ubuntu Core system
  /// and uses this key to onboard the device to a store.
  String? getApiKey() {
    final node = nodeAt(
        const ['hooks', 'prepare-device', 'environment', 'MODEL_APIKEY']);
    return node?.value?.toString();
  }

  /// Sets the `MODEL_APIKEY` environment variable for the `prepare-device`
  /// hook, creating the `hooks` / `prepare-device` / `environment` nesting as
  /// needed. An empty string is a valid (unset) key and is preserved as-is.
  ///
  /// Routes through [update] so any missing intermediate maps are created in
  /// block style and the existing file order is preserved.
  void setApiKey(String key) => update(
      const ['hooks', 'prepare-device', 'environment', 'MODEL_APIKEY'], key);

  // ---------------------------------------------------------------------
  // Slot (snap.yaml) operations
  //
  // Slots are snap-level interface declarations that live in
  // meta/snap.yaml (copied verbatim from the gadget's snapcraft.yaml at
  // build time), not in gadget.yaml. The same [GadgetYaml] instance edits
  // both files, so these helpers act on whichever document the instance
  // was constructed from.
  // ---------------------------------------------------------------------

  /// The `slots` map: slot name → attribute map (`interface` plus any
  /// interface-specific scalar extras such as `path`, `number`,
  /// `chip-number` or `channel`).
  ///
  /// Returns an empty map when the `slots` section is absent, null or not
  /// a map. Attribute order within each slot is preserved.
  Map<String, dynamic> getSlots() {
    final node = nodeAt(const ['slots']);
    if (node is! YamlMap) return const <String, dynamic>{};
    return _convert(node) as Map<String, dynamic>;
  }

  /// Adds a slot declaration to the top-level `slots` map, creating the
  /// section (at the end of the document) on demand.
  ///
  /// [attributes] must contain a non-empty string `interface` plus any
  /// number of interface-specific scalar extras. Throws
  /// [GadgetYamlException] for an invalid [name], a missing or empty
  /// `interface`, an invalid attribute name, a non-scalar attribute value,
  /// or when a slot named [name] already exists (use [setSlot] to replace
  /// an existing slot).
  void addSlot(String name, Map<String, dynamic> attributes) {
    _validateSlotName(name);
    final clean = _validateSlotAttributes(attributes);
    if (has(['slots', name])) {
      throw GadgetYamlException("A slot named '$name' already exists");
    }
    update(['slots', name], clean);
  }

  /// Replaces the attribute map of the existing slot [name], keeping the
  /// slot's position in the `slots` map.
  ///
  /// [attributes] follows the same rules as in [addSlot]. Attributes that
  /// are not passed again are dropped. Throws [GadgetYamlException] if the
  /// slot does not exist (use [addSlot] to create it) or the attributes
  /// are invalid.
  void setSlot(String name, Map<String, dynamic> attributes) {
    _validateSlotName(name);
    final clean = _validateSlotAttributes(attributes);
    final slots = nodeAt(const ['slots']);
    if (slots is! YamlMap || !slots.containsKey(name)) {
      throw GadgetYamlException(
          "No slot named '$name' (use addSlot to create it)");
    }
    _guard(() => _editor.update(['slots', name], _blockNode(clean)));
  }

  /// Removes the slot [name] from the top-level `slots` map.
  ///
  /// When the last slot is removed the whole `slots` section is pruned as
  /// well. Throws [GadgetYamlException] if the section or [name] does not
  /// exist.
  void removeSlot(String name) {
    final slots = nodeAt(const ['slots']);
    if (slots is! YamlMap || !slots.containsKey(name)) {
      throw GadgetYamlException(slots == null
          ? "No 'slots' section in snap YAML"
          : "No slot named '$name'");
    }
    _guard(() {
      _editor.remove(['slots', name]);
      if (_isEmptyMapAt(const ['slots'])) _editor.remove(const ['slots']);
    });
  }

  /// Renames the slot [oldName] to [newName], preserving its attributes.
  ///
  /// The renamed slot moves to the *end* of the `slots` map (mirroring
  /// [renameVolume]). No-op when [oldName] equals [newName]. Throws
  /// [GadgetYamlException] if [oldName] does not exist, [newName] is
  /// invalid, or a slot named [newName] already exists.
  void renameSlot(String oldName, String newName) {
    if (oldName == newName) return;
    _validateSlotName(newName);
    final slots = nodeAt(const ['slots']);
    if (slots is! YamlMap || !slots.containsKey(oldName)) {
      throw GadgetYamlException("No slot named '$oldName'");
    }
    if (slots.containsKey(newName)) {
      throw GadgetYamlException("A slot named '$newName' already exists");
    }
    _guard(() {
      final value = _editor.parseAt(['slots', oldName]);
      _insertNewKey(const [
        'slots'
      ], YamlMapWrap({newName: value}, collectionStyle: CollectionStyle.BLOCK));
      _editor.remove(['slots', oldName]);
    });
  }

  /// Slot names follow the same conservative shape as snap names: letters,
  /// digits, '.', '_' and '-', starting with a letter or digit
  /// (real-world names: `bcm-gpio-512`, `i2c-0`, `bt-serial`, `pwm0`).
  static final RegExp _slotNamePattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  void _validateSlotName(String name) {
    if (name.isEmpty) {
      throw GadgetYamlException('Slot name must not be empty');
    }
    if (!_slotNamePattern.hasMatch(name)) {
      throw GadgetYamlException(
          "Invalid slot name '$name' (allowed: letters, digits, '.', '_' "
          "and '-', starting with a letter or digit)");
    }
  }

  /// Validates a free-form slot attribute map: a non-empty string
  /// `interface` plus any number of interface-specific *scalar* extras.
  /// Returns the entries (in their original order) ready for insertion.
  Map<String, dynamic> _validateSlotAttributes(
      Map<String, dynamic> attributes) {
    final interfaceValue = attributes['interface'];
    if (interfaceValue is! String || interfaceValue.isEmpty) {
      throw GadgetYamlException(
          "A slot requires a non-empty string 'interface' attribute");
    }
    final clean = <String, dynamic>{};
    attributes.forEach((key, value) {
      if (!_slotNamePattern.hasMatch(key)) {
        throw GadgetYamlException(
            "Invalid slot attribute name '$key' (allowed: letters, digits, "
            "'.', '_' and '-', starting with a letter or digit)");
      }
      if (value is List || value is Map) {
        throw GadgetYamlException(
            "Slot attribute '$key' must be a scalar value");
      }
      clean[key] = value;
    });
    return clean;
  }

  /// Removes the top-level volume [name] entirely.
  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Creates any missing intermediate *maps* along [path] (lists are never
  /// created; the terminal segment is left for the caller to act on).
  void _ensureParentMaps(List<Object?> path) {
    for (var depth = 1; depth < path.length; depth++) {
      final prefix = path.sublist(0, depth);
      final node = nodeAt(prefix);
      if (node is YamlMap) continue;
      if (node is YamlList) {
        throw GadgetYamlException(
            "Cannot create a key under the list at '${prefix.join('.')}'");
      }
      // [node] is null: the key is either absent or present with a null
      // value. Either way create it with a placeholder entry, then drop
      // the placeholder (an empty YamlMap()/YamlList() renders in flow
      // style and must be avoided).
      final parentPath = path.sublist(0, depth - 1);
      final parent = nodeAt(parentPath);
      if (parent is YamlList) {
        throw GadgetYamlException(
            "Cannot create a key under the list at '${parentPath.join('.')}'");
      }
      final placeholder = nodeAt(path.sublist(depth)) != null
          ? path.sublist(0, depth + 1)
          : path;
      final body = YamlMapWrap({placeholder.join('.'): ''},
          collectionStyle: CollectionStyle.BLOCK);
      if (parent is YamlMap && parent.containsKey(prefix.last)) {
        // The key exists (with a null value): replace it in place so it
        // keeps its position in the file.
        _editor.update(prefix, body);
      } else {
        // The key is absent: append it at the end of the parent map.
        _insertNewKey(
            parentPath,
            YamlMapWrap({prefix.last: body},
                collectionStyle: CollectionStyle.BLOCK));
      }
      _editor.remove(placeholder);
    }
  }

  T _guard<T>(T Function() body) {
    try {
      return body();
    } on GadgetYamlException {
      rethrow;
    } on YamlException catch (e) {
      throw GadgetYamlException('YAML error: ${e.message}', e);
    } on PathError catch (e) {
      throw GadgetYamlException('Invalid YAML path: $e', e);
    } on AliasException catch (e) {
      throw GadgetYamlException('YAML aliases are not editable: $e', e);
    } on RangeError catch (e) {
      throw GadgetYamlException('Out of range: $e', e);
    } on FormatException catch (e) {
      throw GadgetYamlException('YAML edit rejected: ${e.message}', e);
    }
  }

  bool _isEmptyMapAt(List<Object?> path) {
    final node = nodeAt(path);
    return node is YamlMap && node.isEmpty;
  }

  bool _isEmptyListAt(List<Object?> path) {
    final node = nodeAt(path);
    return node is YamlList && node.isEmpty;
  }

  bool _kernelCmdlineFullyEmpty() {
    final node = nodeAt(const ['kernel-cmdline']);
    if (node is! YamlMap) return false;
    for (final entry in node.nodes.entries) {
      final value = entry.value;
      if (value is YamlList && value.isNotEmpty) return false;
    }
    return true;
  }

  int? _findPartitionIndex(YamlList structure, String partitionName) {
    for (var i = 0; i < structure.length; i++) {
      final element = structure[i];
      if (element is YamlMap && element['name'] == partitionName) {
        return i;
      }
    }
    return null;
  }

  dynamic _convert(dynamic node) {
    if (node is YamlMap) {
      final map = <String, dynamic>{};
      for (final entry in node.nodes.entries) {
        map[entry.key.value.toString()] = _convert(entry.value);
      }
      return map;
    }
    if (node is YamlList) {
      return node.nodes.map(_convert).toList();
    }
    if (node is YamlScalar) return node.value;
    return node;
  }
}
