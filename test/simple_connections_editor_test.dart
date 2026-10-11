import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/simple_connections_editor.dart';
import 'package:gadget_editor/services/snap_lookup_service.dart';
import 'helpers/lookup_fakes.dart';

/// Pumps the editor inside a minimal [MaterialApp] so [Form]/[Navigator]
/// work, and returns the scaffolded app. The editor is add-only, so the
/// [connections] argument is passed but intentionally unused by the widget.
void _noopCancel() {}

Future<void> pumpEditor(
  WidgetTester tester, {
  required String? filePath,
  required Function(dynamic) onSave,
  Function() onCancel = _noopCancel,
  Function(String)? onStatusUpdate,
  SnapLookupService? lookupService,
}) {
  final captured = <String>[];
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SimpleConnectionsEditor(
        connections: null,
        filePath: filePath,
        onSave: onSave,
        onCancel: onCancel,
        onStatusUpdate: onStatusUpdate ?? (m) => captured.add(m),
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

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('connections_editor_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTemp(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  // Returns the parsed document (a YamlMap); callers index it with [operator[]].
  dynamic readBack(String path) =>
      loadYaml(File(path).readAsStringSync());

  Future<void> enterConnection(
    WidgetTester tester, {
    String? plugSnapId,
    required String plug,
    String? slotSnapId,
    String? slot,
  }) async {
    // enterText needs a finder that resolves to the actual TextFormField.
    // widgetWithText(TextFormField, label) matches the field by its
    // decoration label; the two "Snap ID" fields are disambiguated by row
    // order (plug row is first).
    final snapIdFields = find.widgetWithText(TextFormField, 'Snap ID');
    if (plugSnapId != null) {
      await tester.enterText(snapIdFields.first, plugSnapId);
    }
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Interface Plug'), plug);
    if (slotSnapId != null) {
      await tester.enterText(snapIdFields.last, slotSnapId);
    }
    if (slot != null) {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Interface Slot'), slot);
    }
    await tester.pump();
  }

  testWidgets('appends a plug-only connection to an existing list', (tester) async {
    final file = writeTemp('gadget.yaml', '''
name: pc
connections:
  - interface: serial
    plug: modem
''');

    dynamic saved;
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (d) => saved = d,
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterConnection(tester, plug: 'core');
    await tapAdd(tester);

    final conns = readBack(file.path)['connections'] as List;
    expect(conns.length, 2, reason: 'existing entry must survive the append');
    expect(conns[1]['plug'], 'system:core');
    expect(conns[1].containsKey('plugSnapId'), isFalse);
    expect(conns[1].containsKey('slot'), isFalse);
    // First entry untouched.
    expect(conns[0]['plug'], 'modem');
    expect(statuses.last, 'Connection added successfully');
    expect(saved, isA<List>());
  });

  testWidgets('creates the connections section when it is missing', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
    );

    await enterConnection(tester, plug: 'serial');
    await tapAdd(tester);

    final conns = readBack(file.path)['connections'] as List;
    expect(conns.length, 1);
    expect(conns[0]['plug'], 'system:serial');
    // The rest of the document is preserved.
    expect(readBack(file.path)['name'], 'pc');
  });

  testWidgets('stores snap IDs as the combined snap-id:interface form',
      (tester) async {
    // gadget.yaml spec: connections entries are
    //   plug: <plug snap id>:<plug interface>
    //   slot: <slot snap id>:<slot interface>   (optional)
    // never separate plug/plugSnapId/slot/slotSnapId keys.
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final plugId = 'a' * 32;
    final slotId = 'b' * 32;

    dynamic saved;
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (d) => saved = d,
    );

    await enterConnection(
      tester,
      plugSnapId: plugId,
      plug: 'core',
      slotSnapId: slotId,
      slot: 'dbus',
    );
    await tapAdd(tester);

    final conns = readBack(file.path)['connections'] as List;
    final conn = conns[0];
    expect(conn['plug'], '$plugId:core');
    expect(conn['slot'], '$slotId:dbus');
    expect(conn.containsKey('plugSnapId'), isFalse);
    expect(conn.containsKey('slotSnapId'), isFalse);
    // onSave reports the full section, not a single entry.
    expect((saved! as List).length, 1);
  });

  testWidgets('rejects a dangling snap ID that has no interface', (tester) async {
    // A snap ID is meaningless without the interface it qualifies; this is
    // the only cross-field rejection (a bare interface is a valid same-snap
    // connection and must be accepted).
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    // Fill the required plug, then leave a dangling slot snap ID.
    await enterConnection(tester, plug: 'core', slotSnapId: 'b' * 32);
    await tapAdd(tester);

    expect(statuses.last, 'Error: Slot snap ID requires an interface name');
    // Nothing was written.
    expect(readBack(file.path).containsKey('connections'), isFalse);
  });

  testWidgets('qualifies a blank snap ID with the system nick', (tester) async {
    // The spec form is always <snap id>:<interface>; a blank snap ID is
    // qualified with the "system" nick, never stored bare.
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterConnection(tester, plug: 'core', slot: 'dbus');
    await tapAdd(tester);

    expect(statuses.last, 'Connection added successfully');
    final conns = readBack(file.path)['connections'] as List;
    expect(conns[0]['plug'], 'system:core');
    expect(conns[0]['slot'], 'system:dbus');
    expect(conns[0].containsKey('plugSnapId'), isFalse);
    expect(conns[0].containsKey('slotSnapId'), isFalse);
  });

  testWidgets('accepts an explicit system nick', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterConnection(tester, plugSnapId: 'system', plug: 'core');
    await tapAdd(tester);

    expect(statuses.last, 'Connection added successfully');
    final conns = readBack(file.path)['connections'] as List;
    expect(conns[0]['plug'], 'system:core');
  });

  testWidgets('keeps snap ID and interface on one aligned row', (tester) async {
    // The "blank = system" hint must not add a row under the field: both
    // fields of a plug/slot line must share the same height and sit on a
    // single row (regression for the helperText layout break).
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    // No system-shortcut text is shown anywhere in the UI (no under-field
    // helper, no placeholder). The alignment guard below is the real check.
    expect(find.textContaining('system'), findsNothing);

    final fields =
        find.descendant(of: find.byType(Form), matching: find.byType(TextField));
    expect(fields, findsNWidgets(4));

    final plugIdSize = tester.getSize(fields.at(0));
    final plugIfaceSize = tester.getSize(fields.at(1));
    // Same row -> same height, and the snap ID field is wider (flex 5 vs 3).
    expect(plugIdSize.height, plugIfaceSize.height);
    expect(plugIdSize.width, greaterThan(plugIfaceSize.width));
  });

  testWidgets('rejects a malformed plug snap ID', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterConnection(tester, plugSnapId: 'too-short', plug: 'core');
    await tapAdd(tester);

    expect(
        statuses.last,
        'Error: Invalid plug snap ID format. Must be 32 characters');
    expect(readBack(file.path).containsKey('connections'), isFalse);
  });

  testWidgets('rejects an empty plug', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await tapAdd(tester);

    expect(statuses.last, 'Error: Please enter a plug');
    expect(readBack(file.path).containsKey('connections'), isFalse);
  });

  testWidgets('reports an error when no file path is provided', (tester) async {
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: null,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enterConnection(tester, plug: 'core');
    await tapAdd(tester);

    expect(statuses.last, 'Error: No file path provided');
  });

  testWidgets('clears the form fields after a successful save', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(tester, filePath: file.path, onSave: (_) {});

    await enterConnection(tester, plug: 'core');
    await tapAdd(tester);

    await tester.pump();
    expect(find.text('Interface Plug'), findsOneWidget);
    // The controllers were cleared, so the field shows no text.
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Interface Plug'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, isEmpty);
  });

  testWidgets('advertises that a snap name can be typed in the Snap ID fields',
      (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    // Both plug and slot Snap ID fields carry the placeholder, the two
    // interface fields do not (so the total is exactly 2, not 4).
    const hint = 'Snap name or 32-character ID';
    expect(find.text(hint), findsNWidgets(2));
    // And both are attached to the Snap ID fields specifically.
    expect(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Snap ID'),
        matching: find.text(hint),
      ),
      findsNWidgets(2),
      reason: 'the name-search hint belongs to the Snap ID fields only',
    );

  });
}
