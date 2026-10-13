import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/simple_slots_editor.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('slots_editor_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTemp(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  /// Pumps the editor inside a minimal [MaterialApp] so the form and
  /// [Navigator] work, and returns the captured status messages.
  Future<List<String>> pump(
    WidgetTester tester, {
    required String? filePath,
    String mode = 'add',
    String? name,
    Map<String, dynamic>? initialAttributes,
    Function()? onSaved,
  }) async {
    final statuses = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SimpleSlotsEditor(
          mode: mode,
          filePath: filePath,
          name: name,
          initialAttributes: initialAttributes,
          onSave: () => onSaved?.call(),
          onCancel: () {},
          onStatusUpdate: (m) => statuses.add(m),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return statuses;
  }

  Future<void> tapSave(WidgetTester tester, [String label = 'Add']) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  dynamic readBack(String path) => loadYaml(File(path).readAsStringSync());

  group('add mode', () {
    testWidgets('adds a slot with interface and free-form attributes',
        (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      var saved = false;
      await pump(tester, filePath: file.path, onSaved: () => saved = true);

      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 'i2c-1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      // One free-form attribute row ships with the form.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute'), 'path');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Value'), '/dev/i2c-1');

      await tapSave(tester);

      expect(saved, isTrue, reason: 'onSave must fire on success');
      final doc = readBack(file.path);
      expect(doc['slots']['i2c-1'], {'interface': 'i2c', 'path': '/dev/i2c-1'});
    });

    testWidgets('adds multiple attributes via "Add attribute"', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      await pump(tester, filePath: file.path);

      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 'pwm0');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'pwm');

      // Row 1
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute').first, 'chip-number');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Value').first, '0');
      // Add row 2
      await tester.tap(find.text('Add attribute'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute').last, 'channel');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Value').last, '2');

      await tapSave(tester);

      final doc = readBack(file.path);
      expect(doc['slots']['pwm0'],
          {'interface': 'pwm', 'chip-number': '0', 'channel': '2'});
    });

    testWidgets('removes an attribute row before saving', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      await pump(tester, filePath: file.path);

      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's0');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'serial-port');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute'), 'path');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Value'), '/dev/ttyS0');
      // Delete the row again.
      await tester.tap(find.byTooltip('Remove attribute'));
      await tester.pumpAndSettle();

      await tapSave(tester);

      final doc = readBack(file.path);
      expect(doc['slots']['s0'], {'interface': 'serial-port'});
    });

    testWidgets('rejects an invalid slot name', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      final statuses = await pump(tester, filePath: file.path);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), '/dev/i2c-1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tapSave(tester);
      expect(statuses.single, contains('Invalid slot name'));
      expect(readBack(file.path)['slots'], isNull);
    });

    testWidgets('rejects a missing interface', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      final statuses = await pump(tester, filePath: file.path);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's1');
      await tapSave(tester);
      expect(statuses.single, contains('interface'));
      expect(readBack(file.path)['slots'], isNull);
    });

    testWidgets('rejects a duplicate slot name via the service error',
        (tester) async {
      final file = writeTemp(
          'snap.yaml', 'name: pi\nslots:\n  s0:\n    interface: i2c\n');
      final statuses = await pump(tester, filePath: file.path);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's0');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tapSave(tester);
      expect(statuses.single, contains('already exists'));
    });

    testWidgets('rejects an invalid attribute name', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      final statuses = await pump(tester, filePath: file.path);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute'), '/bad');
      await tapSave(tester);
      expect(statuses.single, contains('Invalid attribute name'));
    });

    testWidgets('rejects a duplicate attribute name', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      final statuses = await pump(tester, filePath: file.path);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute'), 'path');
      await tester.tap(find.text('Add attribute'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute').last, 'path');
      await tapSave(tester);
      expect(statuses.single, contains('already set'));
    });

    testWidgets('reports an error when no snap.yaml path is provided',
        (tester) async {
      final statuses = await pump(tester, filePath: null);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tapSave(tester);
      expect(statuses.single, contains('No snap.yaml file path'));
    });

    testWidgets('cancels without writing', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      var saved = false;
      await pump(tester, filePath: file.path, onSaved: () => saved = true);
      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isFalse);
      expect(readBack(file.path)['slots'], isNull);
    });
  });

  group('edit mode', () {
    testWidgets('pre-fills name (locked), interface and attributes',
        (tester) async {
      await pump(
        tester,
        filePath: null,
        mode: 'edit',
        name: 'i2c-0',
        initialAttributes: {'interface': 'i2c', 'path': '/dev/i2c-0'},
      );
      // Name field is pre-filled and locked in edit mode.
      expect(
        find.byWidgetPredicate((w) =>
            w is TextFormField && w.controller?.text == 'i2c-0' && !w.enabled),
        findsOneWidget,
      );
      expect(find.text('i2c'), findsOneWidget);
      expect(find.text('path'), findsOneWidget);
      expect(find.text('/dev/i2c-0'), findsOneWidget);
      // Save button reads "Save" in edit mode, not "Add".
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Add'), findsNothing);
    });

    testWidgets('replaces the full attribute map of the existing slot',
        (tester) async {
      final file = writeTemp('snap.yaml',
          'name: pi\nslots:\n  i2c-0:\n    interface: i2c\n    path: /dev/i2c-0\n');
      var saved = false;
      await pump(
        tester,
        filePath: file.path,
        mode: 'edit',
        name: 'i2c-0',
        initialAttributes: {'interface': 'i2c', 'path': '/dev/i2c-0'},
        onSaved: () => saved = true,
      );
      // Change the interface and drop the path row.
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'serial-port');
      await tester.tap(find.byTooltip('Remove attribute'));
      await tester.pumpAndSettle();
      await tapSave(tester, 'Save');
      expect(saved, isTrue);
      final doc = readBack(file.path);
      expect(doc['slots']['i2c-0'], {'interface': 'serial-port'});
    });

    testWidgets('can add new attributes to an existing slot', (tester) async {
      final file = writeTemp(
          'snap.yaml', 'name: pi\nslots:\n  i2c-0:\n    interface: i2c\n');
      await pump(
        tester,
        filePath: file.path,
        mode: 'edit',
        name: 'i2c-0',
        initialAttributes: {'interface': 'i2c'},
      );
      // A slot whose only attribute is the interface still ships one empty
      // free-form row, which is where the new attribute goes.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Attribute'), 'path');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Value'), '/dev/i2c-0');
      await tapSave(tester, 'Save');
      final doc = readBack(file.path);
      expect(doc['slots']['i2c-0'], {'interface': 'i2c', 'path': '/dev/i2c-0'});
    });

    testWidgets('reports the service error for a missing slot', (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\n');
      final statuses = await pump(
        tester,
        filePath: file.path,
        mode: 'edit',
        name: 'ghost',
        initialAttributes: {'interface': 'i2c'},
      );
      await tapSave(tester, 'Save');
      expect(statuses.single, contains("No slot named 'ghost'"));
    });
  });

  group('show helper', () {
    dynamic readBack(String path) => loadYaml(File(path).readAsStringSync());

    testWidgets('opens an "Add Slot" dialog and adds through it',
        (tester) async {
      final file = writeTemp('snap.yaml', 'name: pi\ntype: gadget\n');
      var saved = false;
      final statuses = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {
              SimpleSlotsEditor.show(
                tester.element(find.byType(ElevatedButton)),
                snapFilePath: file.path,
                onSaved: () => saved = true,
                onStatusUpdate: (m) => statuses.add(m),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add Slot'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Slot name'), 's0');
      await tester.enterText(find.widgetWithText(TextFormField, 'Interface'), 'i2c');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(saved, isTrue);
      expect(readBack(file.path)['slots']['s0'], {'interface': 'i2c'});
      // The dialog is closed.
      expect(find.text('Add Slot'), findsNothing);
    });

    testWidgets('opens an "Edit Slot" dialog with pre-filled values',
        (tester) async {
      final file = writeTemp('snap.yaml',
          'name: pi\nslots:\n  s0:\n    interface: i2c\n    path: /dev/i2c-0\n');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {
              SimpleSlotsEditor.show(
                tester.element(find.byType(ElevatedButton)),
                snapFilePath: file.path,
                onSaved: () {},
                onStatusUpdate: (m) {},
                name: 's0',
                initialAttributes: {'interface': 'i2c', 'path': '/dev/i2c-0'},
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Slot'), findsOneWidget);
      expect(find.text('i2c'), findsOneWidget);
      expect(find.text('/dev/i2c-0'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });
}
