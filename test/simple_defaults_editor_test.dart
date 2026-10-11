// Widget tests for [SimpleDefaultsEditor].
//
// The editor is add-only: it reads the gadget YAML through the service,
// appends a single default, and reports back through [onSave]/[onStatusUpdate].
// Tests round-trip through a real temp file so the on-disk shape (including
// value-type coercion) is what gets asserted.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/simple_defaults_editor.dart';
import 'package:gadget_editor/services/snap_lookup_service.dart';
import 'helpers/lookup_fakes.dart';

/// A valid 32-character snap ID (the editor accepts 32-char IDs or "system").
const String k32 = 'aabbccddeeff00112233445566778899';

void _noopCancel() {}

Future<void> pumpEditor(
  WidgetTester tester, {
  required String? filePath,
  required Function(dynamic) onSave,
  Function() onCancel = _noopCancel,
  required Function(String) onStatusUpdate,
  SnapLookupService? lookupService,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SimpleDefaultsEditor(
        defaults: null,
        filePath: filePath,
        onSave: onSave,
        onCancel: onCancel,
        onStatusUpdate: onStatusUpdate,
        // Hermetic: no real store HTTP from the resolver in tests.
        lookupService: lookupService ?? NoopLookupService(),
      ),
    ),
  ));
}

Future<void> tapAdd(WidgetTester tester) async {
  await tester.tap(find.text('Add'));
  await tester.pump();
}

Future<void> enterDefault(
  WidgetTester tester, {
  required String snapId,
  required String key,
  required String value,
}) async {
  await tester
      .enterText(find.widgetWithText(TextFormField, 'Snap ID'), snapId);
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Key (e.g., foo.bar.baz)'), key);
  await tester
      .enterText(find.widgetWithText(TextFormField, 'Value'), value);
  await tester.pump();
}

/// Toggles the multiline value editor and returns the multiline field.
Future<Finder> expandMultiline(WidgetTester tester) async {
  final toggle = find.byTooltip('Add MultiLine text');
  await tester.tap(toggle);
  await tester.pump();
  return find.widgetWithText(TextFormField, 'Paste multiline text here...');
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('defaults_editor_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTemp(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  dynamic readBack(String path) => loadYaml(File(path).readAsStringSync());

  testWidgets('creates the defaults section and nests dotted keys',
      (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    dynamic saved;
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (d) => saved = d,
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterDefault(tester, snapId: k32, key: 'foo.bar.baz', value: 'x');
    await tapAdd(tester);

    expect(statuses.last, 'Default added successfully');
    final map = readBack(file.path);
    // Dotted key becomes nested maps.
    expect(map['defaults'][k32]['foo']['bar']['baz'], 'x');
    // onSave reports the defaults section.
    expect(saved, isA<Map>());
    expect(saved[k32]['foo']['bar']['baz'], 'x');
  });

  testWidgets('appends to an existing defaults section without clobbering it',
      (tester) async {
    final file = writeTemp(
        'gadget.yaml',
        'name: pc\n'
        'defaults:\n'
        '  system:\n'
        '    existing: keep\n');
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterDefault(tester, snapId: 'system', key: 'added', value: '1');
    await tapAdd(tester);

    final map = readBack(file.path);
    expect(map['defaults']['system']['existing'], 'keep',
        reason: 'existing entries must survive the append');
    expect(map['defaults']['system']['added'], 1);
    expect(statuses.last, 'Default added successfully');
  });

  testWidgets('coerces a boolean value to a real YAML bool', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    await enterDefault(
        tester, snapId: k32, key: 'enabled', value: 'true');
    await tapAdd(tester);

    final map = readBack(file.path);
    expect(map['defaults'][k32]['enabled'], true,
        reason: 'true must be written as a bool, not the string "true"');
  });

  testWidgets('coerces integer and double values to real YAML numbers',
      (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    await enterDefault(tester, snapId: k32, key: 'count', value: '123');
    await tapAdd(tester);
    await enterDefault(tester, snapId: k32, key: 'ratio', value: '1.5');
    await tapAdd(tester);

    final map = readBack(file.path);
    expect(map['defaults'][k32]['count'], 123);
    expect(map['defaults'][k32]['ratio'], 1.5);
  });

  testWidgets('coerces a multiline value into a literal block scalar',
      (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    // Fill the required fields, then expand the multiline editor and enter
    // a multi-line value (the regular Value field is disabled once expanded).
    await tester
        .enterText(find.widgetWithText(TextFormField, 'Snap ID'), k32);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Key (e.g., foo.bar.baz)'),
        'script');
    await tester.pump();
    final multiline = await expandMultiline(tester);
    // The editable surface must fill the fixed-height box, not collapse to a
    // single line at the top (the symptom of a maxLines:null / expands field).
    final editable =
        find.descendant(of: multiline, matching: find.byType(EditableText));
    final editableBox = tester.renderObject(editable) as RenderBox;
    final editableHeight = editableBox.size.height;
    expect(editableHeight, greaterThan(100),
        reason: 'multiline area must fill the box, not be a single line');
    await tester.enterText(multiline, 'line one\nline two');
    await tapAdd(tester);

    final raw = File(file.path).readAsStringSync();
    final map = loadYaml(raw);
    // Round-trips to the exact value.
    expect(map['defaults'][k32]['script'], 'line one\nline two');
    // Written as a literal block scalar (|), not a quoted single line.
    expect(raw, contains('|'));
    expect(raw, isNot(contains('line one\\nline two')));
  });

  testWidgets('rejects a malformed snap ID without modifying the file',
      (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final before = File(file.path).readAsStringSync();
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    // 5 chars: neither "system" nor a 32-char snap ID.
    await enterDefault(tester, snapId: 'short', key: 'k', value: 'v');
    await tapAdd(tester);

    expect(statuses, anyElement(contains('Invalid snap ID')));
    expect(File(file.path).readAsStringSync(), before,
        reason: 'a rejected save must not touch the file');
  });

  testWidgets('accepts the system nick as a snap ID', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    await enterDefault(tester, snapId: 'system', key: 'k', value: 'v');
    await tapAdd(tester);

    final map = readBack(file.path);
    expect(map['defaults']['system']['k'], 'v');
  });

  testWidgets('rejects an empty key', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final before = File(file.path).readAsStringSync();
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    // Valid snap ID so we get past snap validation and hit the empty-key check.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Snap ID'), k32);
    await tester
        .enterText(find.widgetWithText(TextFormField, 'Value'), 'v');
    await tester.pump();
    await tapAdd(tester);

    expect(statuses, anyElement(contains('Please enter a key')));
    expect(File(file.path).readAsStringSync(), before);
  });

  testWidgets('clears the form after a successful save', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    await enterDefault(tester, snapId: k32, key: 'k', value: 'v');
    await tapAdd(tester);

    expect(find.text(k32), findsNothing);
    expect(find.text('k'), findsNothing);
    expect(find.text('v'), findsNothing);
    // The multiline area collapses back down.
    expect(find.byTooltip('Add MultiLine text'), findsOneWidget);
  });

  testWidgets('reports an error when no file path is provided', (tester) async {
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: null,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterDefault(tester, snapId: k32, key: 'k', value: 'v');
    await tapAdd(tester);

    expect(statuses.last, 'Error: No file path provided');
  });

  testWidgets('advertises that a snap name can be typed in the Snap ID field',
      (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    // The hint is a placeholder: it only paints once the empty field is
    // focused, so tap the field to focus it.
    await tester.tap(find.widgetWithText(TextFormField, 'Snap ID'));
    await tester.pump();

    expect(find.text('Snap name or 32-character ID'), findsOneWidget);
  });
}
