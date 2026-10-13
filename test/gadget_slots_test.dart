// Integration tests for the "Slots" section of [GadgetContent]: the section
// is only shown when a snap.yaml is available, renders one card per slot,
// and its add / edit / delete flows round-trip through the snap.yaml file.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/gadget_content.dart';

const _gadgetContent = '''
volumes:
  pc:
    bootloader: grub
    structure:
      - name: root
        size: 1G
''';

const _snapNoSlots = 'name: pi\ntype: gadget\nbase: core24\n';

const _snapWithSlots = '''
name: pi
type: gadget
slots:
  i2c-0:
    interface: i2c
    path: /dev/i2c-0
  pwm0:
    interface: pwm
    chip-number: 0
    channel: 0
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gadget_slots_test.');
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

  /// Pumps the content and gives it a tall viewport so the Slots section
  /// (which sits near the bottom of the page) is on-screen and tappable
  /// without scrolling.
  Future<void> pumpContent(WidgetTester tester, {String? snapFilePath}) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GadgetContent(
          content: _gadgetContent,
          snapFilePath: snapFilePath,
          onStatusUpdate: (m) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The save button of the open slot dialog (the section headers carry
  /// their own "Add" buttons, so scope the lookup to the dialog).
  Finder dialogSaveButton(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  /// Text strictly inside the open slot dialog (the card behind it is
  /// still in the tree and would otherwise also match).
  Finder dialogText(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  testWidgets('hides the Slots section when no snap.yaml is loaded',
      (tester) async {
    await pumpContent(tester);
    expect(find.text('Slots'), findsNothing);
  });

  testWidgets(
      'shows the empty state with an add affordance when snap.yaml has no slots',
      (tester) async {
    final file = writeTemp('snap.yaml', _snapNoSlots);
    await pumpContent(tester, snapFilePath: file.path);
    expect(find.text('Slots'), findsOneWidget);
    expect(
      find.text('No slots yet. Declare snap interface slots.'),
      findsOneWidget,
    );
    expect(find.text('Add Slots'), findsOneWidget);
  });

  testWidgets('renders one card per slot with interface and attributes',
      (tester) async {
    final file = writeTemp('snap.yaml', _snapWithSlots);
    await pumpContent(tester, snapFilePath: file.path);
    expect(find.text('i2c-0'), findsOneWidget);
    expect(find.text('Interface: '), findsNWidgets(2));
    expect(find.text('i2c'), findsOneWidget);
    expect(find.text('path: /dev/i2c-0'), findsOneWidget);
    expect(find.text('pwm0'), findsOneWidget);
    expect(find.text('pwm'), findsOneWidget);
    expect(find.text('chip-number: 0'), findsOneWidget);
    expect(find.text('channel: 0'), findsOneWidget);
    // Both cards offer edit and delete.
    expect(find.byTooltip('Edit slot'), findsNWidgets(2));
    expect(find.byTooltip('Delete slot'), findsNWidgets(2));
  });

  testWidgets('adds a slot through the empty-state Add button', (tester) async {
    final file = writeTemp('snap.yaml', _snapNoSlots);
    await pumpContent(tester, snapFilePath: file.path);

    await tester.tap(find.text('Add Slots'));
    await tester.pumpAndSettle();
    expect(find.text('Add Slot'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Slot name'), 'i2c-1');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Interface'), 'i2c');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Attribute'), 'path');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Value'), '/dev/i2c-1');
    await tester.tap(dialogSaveButton('Add'));
    await tester.pumpAndSettle();

    // Persisted to the snap.yaml on disk...
    expect(readBack(file.path)['slots']['i2c-1'],
        {'interface': 'i2c', 'path': '/dev/i2c-1'});
    // ...and the section re-rendered with the new card.
    expect(find.text('i2c-1'), findsOneWidget);
    expect(find.text('path: /dev/i2c-1'), findsOneWidget);
  });

  testWidgets('edits a slot through the card edit button', (tester) async {
    final file = writeTemp('snap.yaml', _snapWithSlots);
    await pumpContent(tester, snapFilePath: file.path);

    // Edit the first card (i2c-0).
    await tester.tap(find.byTooltip('Edit slot').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Slot'), findsOneWidget);
    // Pre-filled values are visible in the dialog (scoped, because the
    // card behind the dialog carries the same strings).
    expect(dialogText('i2c'), findsOneWidget);
    expect(dialogText('path'), findsOneWidget);
    expect(dialogText('/dev/i2c-0'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Interface'), 'serial-port');
    await tester.tap(dialogSaveButton('Save'));
    await tester.pumpAndSettle();

    expect(readBack(file.path)['slots']['i2c-0'],
        {'interface': 'serial-port', 'path': '/dev/i2c-0'});
    expect(find.text('serial-port'), findsOneWidget);
  });

  testWidgets('deletes a slot through the card trash icon with confirmation',
      (tester) async {
    final file = writeTemp('snap.yaml', _snapWithSlots);
    await pumpContent(tester, snapFilePath: file.path);

    await tester.tap(find.byTooltip('Delete slot').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Slot'), findsOneWidget);

    // Cancel first: nothing is removed.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(readBack(file.path)['slots']['i2c-0'], isNotNull);
    expect(find.text('i2c-0'), findsOneWidget);

    // Delete for real.
    await tester.tap(find.byTooltip('Delete slot').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(readBack(file.path)['slots']['i2c-0'], isNull);
    expect(readBack(file.path)['slots']['pwm0'], isNotNull);
    expect(find.text('i2c-0'), findsNothing);
    expect(find.text('pwm0'), findsOneWidget);
  });

  testWidgets(
      'prunes the section back to the empty state when the last slot is deleted',
      (tester) async {
    final file = writeTemp('snap.yaml',
        'name: pi\ntype: gadget\nslots:\n  s0:\n    interface: i2c\n');
    await pumpContent(tester, snapFilePath: file.path);

    await tester.tap(find.byTooltip('Delete slot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(readBack(file.path)['slots'], isNull);
    expect(find.text('No slots yet. Declare snap interface slots.'),
        findsOneWidget);
  });
}
